/*
 * rudf_native — a thin, crash-safe C bridge to the MuPDF engine.
 *
 * MuPDF reports errors through fz_try/fz_catch (setjmp/longjmp), which cannot
 * be crossed safely by pure Ruby-FFI. Every MuPDF call here is wrapped so that
 * a C-level error is turned into a Ruby exception instead of unwinding through
 * the Ruby VM. This is the same design PyMuPDF uses (via SWIG wrappers).
 *
 * The extension is optional: when MuPDF is not present at build time,
 * extconf.rb produces a no-op Makefile and this file is never compiled, so the
 * gem still installs and runs in pure-Ruby mode.
 */

#include <ruby.h>
#include <mupdf/fitz.h>
#include <string.h>

static fz_context *g_ctx = NULL;

/* Lazily create (once) the shared MuPDF context. */
static fz_context *rudf_ctx(void) {
    if (g_ctx == NULL) {
        g_ctx = fz_new_context(NULL, NULL, FZ_STORE_DEFAULT);
        if (g_ctx == NULL) {
            rb_raise(rb_eRuntimeError, "rudf_native: failed to create MuPDF context");
        }
        fz_try(g_ctx) {
            fz_register_document_handlers(g_ctx);
        }
        fz_catch(g_ctx) {
            fz_drop_context(g_ctx);
            g_ctx = NULL;
            rb_raise(rb_eRuntimeError, "rudf_native: failed to register document handlers");
        }
    }
    return g_ctx;
}

/* ---- document wrapper (GC-managed) ------------------------------------- */

typedef struct {
    fz_document *doc;
} rudf_document_t;

static void rudf_document_free(void *p) {
    rudf_document_t *d = (rudf_document_t *)p;
    if (d) {
        if (d->doc && g_ctx) {
            fz_drop_document(g_ctx, d->doc);
        }
        xfree(d);
    }
}

static size_t rudf_document_size(const void *p) {
    (void)p;
    return sizeof(rudf_document_t);
}

static const rb_data_type_t rudf_document_type = {
    "rudf_native/document",
    { NULL, rudf_document_free, rudf_document_size },
    NULL, NULL, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE cDocument;

static rudf_document_t *rudf_get_document(VALUE self) {
    rudf_document_t *d;
    TypedData_Get_Struct(self, rudf_document_t, &rudf_document_type, d);
    if (d->doc == NULL) {
        rb_raise(rb_eRuntimeError, "rudf_native: document is closed");
    }
    return d;
}

/* ---- open --------------------------------------------------------------- */

/* NativeExt.open(bytes) -> Document */
static VALUE rudf_open(VALUE klass, VALUE data) {
    fz_context *ctx = rudf_ctx();
    fz_buffer *buf = NULL;
    fz_stream *stm = NULL;
    fz_document *doc = NULL;

    Check_Type(data, T_STRING);

    fz_var(buf);
    fz_var(stm);
    fz_try(ctx) {
        buf = fz_new_buffer_from_copied_data(ctx,
                (const unsigned char *)RSTRING_PTR(data), (size_t)RSTRING_LEN(data));
        stm = fz_open_buffer(ctx, buf);
        doc = fz_open_document_with_stream(ctx, ".pdf", stm);
    }
    fz_always(ctx) {
        fz_drop_stream(ctx, stm);
        fz_drop_buffer(ctx, buf);
    }
    fz_catch(ctx) {
        rb_raise(rb_eRuntimeError, "rudf_native: MuPDF failed to open the document");
    }

    rudf_document_t *d;
    VALUE obj = TypedData_Make_Struct(cDocument, rudf_document_t, &rudf_document_type, d);
    d->doc = doc;
    (void)klass;
    return obj;
}

/* document.close -> nil */
static VALUE rudf_close(VALUE self) {
    rudf_document_t *d;
    TypedData_Get_Struct(self, rudf_document_t, &rudf_document_type, d);
    if (d->doc && g_ctx) {
        fz_drop_document(g_ctx, d->doc);
        d->doc = NULL;
    }
    return Qnil;
}

/* document.page_count -> Integer */
static VALUE rudf_page_count(VALUE self) {
    rudf_document_t *d = rudf_get_document(self);
    fz_context *ctx = rudf_ctx();
    int count = 0;
    fz_try(ctx) {
        count = fz_count_pages(ctx, d->doc);
    }
    fz_catch(ctx) {
        rb_raise(rb_eRuntimeError, "rudf_native: failed to count pages");
    }
    return INT2NUM(count);
}

/* document.metadata(key) -> String or nil */
static VALUE rudf_metadata(VALUE self, VALUE key) {
    rudf_document_t *d = rudf_get_document(self);
    fz_context *ctx = rudf_ctx();
    char out[1024];
    int n = 0;
    fz_try(ctx) {
        n = fz_lookup_metadata(ctx, d->doc, StringValueCStr(key), out, (int)sizeof(out));
    }
    fz_catch(ctx) {
        rb_raise(rb_eRuntimeError, "rudf_native: metadata lookup failed");
    }
    return (n > 0) ? rb_utf8_str_new_cstr(out) : Qnil;
}

/* ---- render ------------------------------------------------------------- */

/*
 * document.render(page, a, b, c, d, e, f, alpha, gray)
 *   -> [width, height, components, samples]
 *
 * The six numbers are a full affine transform (fz_matrix). Samples are packed
 * interleaved bytes with `components` channels per pixel.
 */
static VALUE rudf_render(VALUE self, VALUE page, VALUE ma, VALUE mb, VALUE mc,
                         VALUE md, VALUE me, VALUE mf, VALUE alpha, VALUE gray) {
    rudf_document_t *d = rudf_get_document(self);
    fz_context *ctx = rudf_ctx();
    fz_pixmap *pix = NULL;
    fz_colorspace *cs;
    VALUE result = Qnil;

    fz_matrix ctm;
    ctm.a = (float)NUM2DBL(ma);
    ctm.b = (float)NUM2DBL(mb);
    ctm.c = (float)NUM2DBL(mc);
    ctm.d = (float)NUM2DBL(md);
    ctm.e = (float)NUM2DBL(me);
    ctm.f = (float)NUM2DBL(mf);

    cs = RTEST(gray) ? fz_device_gray(ctx) : fz_device_rgb(ctx);

    fz_var(pix);
    fz_try(ctx) {
        pix = fz_new_pixmap_from_page_number(ctx, d->doc, NUM2INT(page), ctm, cs,
                                             RTEST(alpha) ? 1 : 0);
        int w = fz_pixmap_width(ctx, pix);
        int h = fz_pixmap_height(ctx, pix);
        int n = fz_pixmap_components(ctx, pix);
        unsigned char *samples = fz_pixmap_samples(ctx, pix);
        VALUE bytes = rb_str_new((const char *)samples, (long)w * h * n);
        result = rb_ary_new3(4, INT2NUM(w), INT2NUM(h), INT2NUM(n), bytes);
    }
    fz_always(ctx) {
        fz_drop_pixmap(ctx, pix);
    }
    fz_catch(ctx) {
        rb_raise(rb_eRuntimeError, "rudf_native: failed to render page");
    }
    return result;
}

/* ---- text --------------------------------------------------------------- */

/* document.text(page) -> String (UTF-8) */
static VALUE rudf_text(VALUE self, VALUE page) {
    rudf_document_t *d = rudf_get_document(self);
    fz_context *ctx = rudf_ctx();
    fz_stext_page *stext = NULL;
    fz_buffer *buf = NULL;
    fz_output *out = NULL;
    VALUE result = Qnil;

    fz_var(stext);
    fz_var(buf);
    fz_var(out);
    fz_try(ctx) {
        stext = fz_new_stext_page_from_page_number(ctx, d->doc, NUM2INT(page), NULL);
        buf = fz_new_buffer(ctx, 1024);
        out = fz_new_output_with_buffer(ctx, buf);
        fz_print_stext_page_as_text(ctx, out, stext);
        fz_close_output(ctx, out);

        unsigned char *data = NULL;
        size_t len = fz_buffer_storage(ctx, buf, &data);
        result = rb_utf8_str_new((const char *)data, (long)len);
    }
    fz_always(ctx) {
        fz_drop_output(ctx, out);
        fz_drop_buffer(ctx, buf);
        fz_drop_stext_page(ctx, stext);
    }
    fz_catch(ctx) {
        rb_raise(rb_eRuntimeError, "rudf_native: failed to extract text");
    }
    return result;
}

/* ---- init --------------------------------------------------------------- */

void Init_rudf_native(void) {
    VALUE mRUDF = rb_define_module("RUDF");
    VALUE mNative = rb_define_module_under(mRUDF, "NativeExt");

    rb_define_const(mNative, "MUPDF_VERSION", rb_str_new_cstr(FZ_VERSION));

    cDocument = rb_define_class_under(mNative, "Document", rb_cObject);
    rb_undef_alloc_func(cDocument);

    rb_define_singleton_method(mNative, "open", rudf_open, 1);
    rb_define_method(cDocument, "close", rudf_close, 0);
    rb_define_method(cDocument, "page_count", rudf_page_count, 0);
    rb_define_method(cDocument, "metadata", rudf_metadata, 1);
    rb_define_method(cDocument, "render", rudf_render, 9);
    rb_define_method(cDocument, "text", rudf_text, 1);
}
