# TCAM 

TCAM is a little cinematic camera experiment for the iPhone — part camera, part film lab, and part excuse to make ordinary walks look like the opening scene of a movie.

It explores Technicolor-inspired film processes, expressive color, lens switching, exposure controls, and photo watermarks through a dark, tactile interface.

Built for fun, curiosity, and the occasional happy accident.

## Image pipeline

The broader image-making direction is:

```text
ProRAW DNG
   ↓
CIImage / CIRAWFilter
   ↓
Metal processing
   ↓
Extended-linear / wide-gamut processing
   ↓
Tone map + final color transform
   ↓
Display P3
   ↓
JPEG
   ↓
Instagram 4:5, including the watermark
```

The current implementation already applies the Technicolor-inspired Core Image processing, aspect-ratio crop, Display P3 output, and watermark before saving the photo. ProRAW/CIRAWFilter input, dedicated Metal processing, and the final Instagram 4:5 export stage are part of the continuing image pipeline work.
