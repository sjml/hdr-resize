# HDR Resize
If you export an HDR image taken with an iPhone, either as HEIC or JPEG, the data that makes it HDR is stored in something called a gain map. It's a little hacky (though apparently [on its way to standardization](https://www.iso.org/standard/86775.html)) but the gain map is stuffed into the metadata of both formats, even though HEIC supports multi-image files. ¯\\\_(ツ)_/¯ Unfortunately, as of this writing in June 2025, most command-line tools simply discard that data when you process the image, so it's hard to resize it as part of a workflow. 

So I wrote this simple Swift command-line app to do nothing but resize HDR images in these formats. I hope that soon ImageMagick, sips, vips, etc. will all start supporting this kind of data naturally so I don't need this anymore. In the meanwhile, here it is in case anybody else wants it. 

## Installation
`brew install sjml/sjml/hdr-resize`

## Usage
```
hdr-resize --input <input> --output <output> --size-string <size-string> [--quality <quality>]

OPTIONS:
  -i, --input <input>     Path to the input image
  -o, --output <output>   Path to the output image
  -s, --size-string <size-string>
                          Desired size in the format WxH, Wx, or xH
  -q, --quality <quality> Output image quality (0-100) (default: 85)
  -h, --help              Show help information.
```

## Notes
* Only runs on Macs because it uses Apple's image processing libraries; sorry.
* It assumes that the gain map is half-resolution of the image, which seems to be the standard.
* It has not been fully tested with a wide variety of images, different orientations, etc.
  * Any bugs that emerge from that kind of diversity should be fairly easy to spot and figure out, though.
* I built this on an M1 Mac running Sequoia 15.5 with Swift 6.1.2. No idea if it builds on older versions of Swift/macOS, Intel, etc. 
* Only handles HEIC and JPEG images (both input and output).
* Only handles HDR images; if you try to load a file that does not have a gain map, it will throw an error. 
* Note that on very low quality settings the compression doesn't seem to be as aggressive as, say, ImageMagick's; I care more about preserving quality so this isn't an issue for me, but if you're keen to squeeze out compression maximization, this may not be the tool for you. (I think it's because of how Apple's image libraries work, but unsure.)

## References
* [Apple documentation, which leaves a lot out](https://developer.apple.com/documentation/appkit/applying-apple-hdr-effect-to-your-photos)
* [The proposed ISO standard](https://www.iso.org/standard/86775.html)
* [ImageMagick issue about integrating gain map support](https://github.com/ImageMagick/ImageMagick/issues/6377) (lots of good references in there, too)
  * indicates there *should* be ways of getting ImageMagick to work with gain maps, but I was never able to do it, and the flags are not documented
* [Google's libultrahdr](https://github.com/google/libultrahdr) which looks promising but also very low-level
* Two posts from JuniperPhoton explaining how to extract existing gain map data and calculate the headroom, etc. 
  * https://juniperphoton.substack.com/p/process-apple-gain-map-the-imageio
  * https://juniperphoton.substack.com/p/decoding-some-hidden-magic-of-makerapple
  * (I don't actually do any manipulation of the gain map other than resizing it, it so no need to recalculate its meta values, but these posts explain how to do that just in case it ever comes up, and I don't want to have to search for them again)
