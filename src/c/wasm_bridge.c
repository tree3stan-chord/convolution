// wasm_bridge.c – public, JS‑friendly wrappers
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* ---- prototypes of the internal (“underscore”) functions ---- */
void init_convolution_engine_(int *sr);
void process_convolution_(double *in, double *out, int *n);
void set_param_float_(int *param_id, float *value);
void set_ir_type_(char *str, int len);
void cleanup_convolution_engine_(void);
int  is_initialized_(void);
int  get_sample_rate_(void);
char *get_version_(void);

/* ---- simple memory helpers expected by JS ---- */
void *allocate_double_array(int n)      { return calloc(n, sizeof(double)); }
void  free_double_array(void *p)        { free(p); }

/* ---- public wrappers -------------------------------------------------- */
void init_engine(int sr)                          { init_convolution_engine_(&sr);             }
void process_audio(double *in,double *out,int n)  { process_convolution_(in,out,&n);          }
void set_parameter(int id, float v)               { set_param_float_(&id, &v);                 }
void set_ir_type(const char *s)                   { int len=strlen(s); set_ir_type_((char*)s,len); }
void cleanup_engine(void)                         { cleanup_convolution_engine_();             }
int  is_initialized(void)                         { return is_initialized_();                  }
int  get_sample_rate(void)                        { return get_sample_rate_();                 }
const char *get_version(void)                     { return get_version_();                     }

/* optional stub, exported to satisfy the old list */
void process_audio_with_mix(double *in,double *out,int n,float wet) {
    process_audio(in,out,n); /* passthrough for now */
}