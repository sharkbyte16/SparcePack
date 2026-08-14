unit Options;

{$I compiler.inc}

interface

uses
    SysUtils, getopts,
    Consts;

type
    TAppOptions = record
        InputFile : string;
        OutputFile : string;
        ForceOverwrite : Boolean;
        CheckPacked : Boolean;
        Verbose : Boolean;
        Action : string;              // pack | unpack
        BlockSize : Integer;          // -1 = not set
    end;

procedure GetOptions(var Opts : TAppOptions);

implementation


procedure Usage;
begin
    WriteLn(PACKNAME, ' version ',PACKVER,'. ', PACKCR);
    WriteLn('Packs a sparce file or inflates a packed file.');
    WriteLn('sparce infile [-o outfile] [-b blocksize] [-f] [-c] [-v]');
	WriteLn('       -o : output filename');
    WriteLn('       -f : force overwite existing outfile');
    WriteLn('       -b : block size in bytes for packing');
    WriteLn('       -c : check packed file unpacks to original');
    WriteLn('       -v : verbose');
end;


procedure ParseOpts(var Opts : TAppOptions);
var
    Options: array[1..6] of TOption;
    C: Char;
    OptionIndex: LongInt;
begin
	with Opts do begin
        InputFile := '';
        OutputFile := '';
        ForceOverwrite := False;
        CheckPacked := False;
        Verbose := False;
        Action := 'pack';
        BlockSize := -1;
	end;

    OptErr := False;

    // Configure supported options:
    with Options[1] do begin
        name := 'f';
        has_arg := 0;
        flag := nil;
		value := #0;
    end;
    with Options[2] do begin
        name := 'c';
        has_arg := 0;
        flag := nil;
        value := #0;
    end;
    with Options[3] do begin
        name := 'v';
        has_arg := 0;
        flag := nil;
        value := #0;
    end;
	with Options[4] do begin
        name := 'o';
        has_arg := Required_argument;
        flag := nil;
        value := #0;
	end;
    with Options[5] do begin
        name := 'b';
        has_arg := Required_argument;
        flag := nil;
        value := #0;
	end;
    with Options[6] do begin
	    // terminator
        name := '';
        has_arg := 0;
        flag := nil;
	end;

    // Parse options (single-letter short options only)
    C := #0;
    repeat
        C := GetLongOpts('fcvo:b:', @Options[1], OptionIndex);

        if C in ['?','!'] then
        begin
            Usage;
            raise Exception.Create('Invalid command line option: -'+ OptOpt);
        end;

        case C of
            'f': Opts.ForceOverwrite := True;
            'c': Opts.CheckPacked := True;
            'v': Opts.Verbose := True;
            'o': Opts.OutputFile := OptArg;
            'b': begin
                     try
                         Opts.BlockSize := StrToInt(OptArg);
                     except
                         on E : EConvertError do raise Exception.Create('Invalid block size'+OptArg);
                     end;
                 end;
        end;
    until C=EndOfOptions;

    // Remaining argument is the required input file
    if OptInd > ParamCount then
    begin
        Usage;
        raise Exception.Create('Missing <inputfile>');
    end;

    Opts.InputFile := ParamStr(OptInd);
    Inc(OptInd);

    // No extra args allowed (optional; remove if you want to allow more)
    if OptInd <= ParamCount then
    begin
        Usage;
        raise Exception.CreateFmt('Unexpected extra argument: %s', [ParamStr(OptInd)]);
    end;

    // Validate block size if provided
    if Opts.BlockSize <> -1 then
    begin
        if Opts.BlockSize <= 0 then
        begin
            Usage;
            raise Exception.Create('Block size must be a positive integer.');
        end;
    end;

    if Opts.InputFile = '' then
    begin
        Usage;
        raise Exception.Create('Inputfile cannot be empty.');
    end;
end;


procedure GetOptions(var Opts : TAppOptions);
var
    InExt, OutExt : String;
begin
    try
        ParseOpts(Opts);
    except
        on E: Exception do
        begin
            Writeln('Error: ', E.Message);
            Halt(1);
        end;
    end;
    with Opts do begin
        if BlockSize = -1 then BlockSize := PACKBLKSIZE;
        // infile extension
        InExt  := ExtractFileExt(InputFile);
        if LowerCase(InExt) = PACKEXT then begin
            // We are unpacking
            Action := 'unpack';
            // Output filename not specified --> remove extension from the input filename
            if OutputFile = '' then OutputFile := LeftStr(InputFile, Length(InputFile) - Length(PACKEXT));
            // If output extension is PACKEXT --> append 'unpacked'
            OutExt := ExtractFileExt(OutputFile);
            if LowerCase(OutExt) = PACKEXT then OutputFile := OutputFile + '.unpacked';
            if CheckPacked then WriteLn('Note: -c only applies when packing; ignored for unpacking.');
        end
        else begin
            // We are packing
		    Action := 'pack';
            // Output filename, if not specified append extension to input filename
            if OutputFile = '' then OutputFile := InputFile + PACKEXT;
            // else check for correct extension, if not, append it
            OutExt := ExtractFileExt(OutputFile);
            if LowerCase(OutExt) <> PACKEXT then OutputFile := OutputFile + PACKEXT;
        end;
    end; // with
end;

begin
end.
