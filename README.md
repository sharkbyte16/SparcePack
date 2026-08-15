What is SparcePack?
===================
SparcePack is a small command line utility to pack/unpack sparce files. It's primary use is to 'unsparce' large sparce file such as disk image to a packed file ready for upload to cloud storage services that refuse sparce files. As an added benefit, depending on how sparce a file is, it can significantly reduce the file size. 

Features
--------
- Fast! As no data processing is involved beyond null value removal, sparce packing should be much faster than file compression.
- Packed files store a hash to verify unpacking
- Automatic selection of packing/unpacking based on input file 

Usage
-----
```
sparce infile [-o outfile] [-b blocksize] [-f] [-c] [-v]
	-o : output filename
	-f : force overwite existing outfile
	-b : block size in bytes for packing
	-c : check packed file unpacks to original
	-v : verbose
```

Warning alpha stage
--------------------
This is a new tool, still in alpha stage. Data integrity not guaranteed and file format may still change. 
**Don't use for backup!**

Build
-----
SparcePack is using the FreePascal 3.2+ on Linux x86_64, it may compile on other platforms supported by FreePascal.
To build SparcePack, simply run `fpc sparce.pas` or run the `build.sh` script.

