# HDR Resizer

If you export an HDR image taken with an iPhone, either as HEIC or JPEG, the data that makes it HDR is stored in something called a gain map. It's a little hacky, but apparently on its way to standardization, to include this data in the image metadata in both formats. Unfortunately (as of this writing in June 2025) most command-line tools simply discard this data when you process the image, so it's hard to resize it as part of a workflow. 

So I wrote this simple Swift command-line app to do nothing but resize HDR images in these formats. I hope that soon ImageMagick, sips, vips, etc. will all start supporting this kind of data naturally so I don't need this anymore. In the meanwhile, here it is in case anybody else wants it. 

