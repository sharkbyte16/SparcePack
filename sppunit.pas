{###############################################################################

 Sparce Pack File format:
 +------------------------+
 | File header            |
 | Header CRC32           |
 | Duplicate header       |
 | Duplicate header CRC32 |
 +------------------------+
 | Sparce                 |
 | [Block data]           |
 | Sparce                 |
 | [Block data]           |
 | ...                    |
 +------------------------+

 File Header:
 Magic        :  6 bytes : 'SPRSPK'
 Version      :  2 bytes : array [0..1] of byte
 BlockSize    :  4 bytes : LongWord
 OrgSize      :  8 bytes : Int64
 NrBlocks     :  8 bytes : Int64
 LastBlock    :  4 bytes : LongWord
 MD5Hash      : 16 bytes : TMD5Digest

 Header CRC32 :  4 bytes : Cardinal

 Sparce         : 1 byte
 Block data     : array[0..Blocksize-1] of byte

###############################################################################}

unit SppUnit;

{$I compiler.inc}

interface

uses
    Classes, SysUtils, getopts, Math, md5, crc,
    Consts, Options, Misc;

type
    THeader = packed record
        Magic      : array[0..Length(PACKMAGIC)-1] of Byte;
        Version    : array[0..1] of Byte;
        BlockSize  : LongWord;
        OrgSize    : Int64;
        NrBlocks   : Int64;
        LastBlock  : LongWord;
        MD5Hash    : TMD5Digest;
    end;

    TBlock = array of Byte;

    TSparsePacker = record
        AppOptions : TAppOptions;
        Header : THeader;
        FSin, FSout : TFileStream;
        Buff, ZeroBuff : TBlock;
    end;

procedure InitHeader(var SP : TSparsePacker);
procedure PrintHeader(SP : TSparsePacker);
procedure CreateOutFile(var SP : TSparsePacker);
procedure InitBuff(var Buff : TBlock; Size : LongWord);
procedure GetParams(var SP : TSparsePacker);

procedure ProbePackInfile(var SP : TSparsePacker);
function IsZeroBlock(const Buffer: TBlock; Size: LongWord): Boolean;
Procedure SppPack(var SP : TSparsePacker);

procedure ProbeUnpackInfile(var SP : TSparsePacker);
procedure SppUnpack(var SP : TSparsePacker; NoWrite : Boolean);

implementation

// --- exposed generic routines ----------------------

procedure InitHeader(var SP : TSparsePacker);
var
    i : Byte;
begin
    with SP.Header do begin
        for i := 0 to Length(PACKMAGIC)-1 do Magic[i] := Ord(PACKMAGIC[i+1]);
        Version[0]  := Byte(StrToInt(LeftStr(PACKVER, Pos('.', PACKVER) - 1)));
        Version[1]  := Byte(StrToInt(Copy(PACKVER, Pos('.', PACKVER) + 1, MaxInt)));
        BlockSize := PACKBLKSIZE;
    end;
end;

procedure PrintHeader(SP : TSparsePacker);
var
    i : Integer;
begin
    with SP.Header do begin
        Write(  '  Magic     '); for i := 0 to Length(PACKMAGIC)-1 do Write(Chr(Magic[i])); WriteLn;
        WriteLn('  Version   ', Version[0],'.',Version[1]);
        WriteLn('  OrgSize   ', OrgSize    );
        WriteLn('  BlockSize ', BlockSize  );
        WriteLn('  NrBlocks  ', NrBlocks   );
        WriteLn('  LastBlock ', LastBlock  );
        Write(  '  MD5Hash   '); for i := 0 to 15 do Write(IntToHex(MD5Hash[i])); WriteLn;
    end;
end;


procedure CreateOutFile(var SP : TSparsePacker);
var
    OutputFile : String;
begin
    OutputFile := SP.AppOptions.OutputFile;
    if SP.AppOptions.Verbose then WriteLn('* Creating outpute file: '+OutputFile);

    with SP.AppOptions do begin
        if (FileExists(OutputFile) = True) and (ForceOverwrite = False) then begin
            Raise Exception.Create('Output file '+OutputFile+' exists, use option -f to force overwrite.');
        end;
    end;
    SP.FSout := nil;
    Sp.FSout := TFileStream.Create(OutputFile, fmCreate or fmShareExclusive);
end;


procedure InitBuff(var Buff : TBlock; Size : LongWord);
var
    i : LongWord;
begin
    SetLength(Buff, Size);
    for i := 0 to Size-1 do Buff[i] := 0;
end;


procedure GetParams(var SP : TSparsePacker);
begin
    GetOptions(SP.AppOptions);
    SP.Header.BlockSize := SP.AppOptions.BlockSize;
end;

// --- exposed pack routines ----------------------

procedure ProbePackInfile(var SP : TSparsePacker);
var
    Size : Int64 = 0;
    Hash : TMD5Digest;
    InFileName : String;
begin
    InFileName := SP.AppOptions.InputFile;
    if SP.AppOptions.Verbose then WriteLn('* Probing: '+InFileName+' ...');
    SP.FSin := nil;
    SP.FSin := TFileStream.Create(InFileName, fmOpenRead or fmShareDenyWrite);
    Size := SP.FSin.Size;
    if Size = 0 then begin
		raise Exception.Create('Empty file "'+InFileName+'": Nothing to pack');
    end;

    Hash := DummyMD5Hash; // postponed to processing file

    with SP.Header do begin
        OrgSize   := Size;
        NrBlocks  := Ceil(OrgSize / BlockSize);
        LastBlock := OrgSize - (NrBlocks-1)*BlockSize;
        MD5Hash   := Hash;
    end;

    {$IFDEF DEBUG}
        if SP.AppOptions.Verbose then PrintHeader(SP);
    {$ENDIF}
end;


function IsZeroBlock(const Buffer: TBlock; Size: LongWord): Boolean;
var
    PW: PNativeUInt;
    PB: PByte;
    i, Words, Remainder: LongWord;
begin
    if Size = 0 then Exit(True);
    Words := Size div SizeOf(NativeUInt);
    Remainder := Size mod SizeOf(NativeUInt);
    PW := @Buffer[0];
    // Check full machine words
    for i := 1 to Words do begin
        if PW^<> 0 then Exit(False);
        Inc(PW);
    end;
    // Check remaining bytes
    PB := PByte(PW);
    for i := 1 to Remainder do begin
        if PB^ <> 0 then Exit(False);
        Inc(PB);
    end;
    Result := True;
end;


Procedure SppPack(var SP : TSparsePacker);
var
    BlockNr : Int64;
    Sparce : Byte;
    NrBytesRead : Int64;
    PackedSize : Int64;
    MD5Context : TMD5Context;
    Hash : TMD5Digest;
    CRC : Cardinal;
begin

    with SP do begin

        if SP.AppOptions.Verbose then Write('* Packing: '+AppOptions.InputFile+': ');

        CRC := crc32(0, nil, 0);                   // reset CRC
        CRC := crc32(CRC, @Header, SizeOf(Header)); // calc header CRC

        FSout.WriteBuffer(Header, SizeOf(Header)); // write out header still with dummy hash
        FSout.WriteBuffer(CRC, SizeOf(CRC));       // and write out CRC
        FSout.WriteBuffer(Header, SizeOf(Header)); // write out duplicate header still with dummy hash
        FSout.WriteBuffer(CRC, SizeOf(CRC));       // and write out duplicate header CRC

        MD5Init(MD5Context);

        // Just to be sure the file is reset
        SP.FSin.Seek(0, soBeginning);

        // Write every full-size block
        for BlockNr := 1 to Header.NrBlocks-1 do begin


            NrBytesRead := FSin.Read(Buff[0], Header.BlockSize);
            MD5Update(MD5Context, Buff[0], NrBytesRead);
            if NrBytesRead = 0 then begin
                raise Exception.Create('Error packing -- file truncated file during reading '+SP.AppOptions.InputFile);
            end;

            if IsZeroBlock(Buff, NrBytesRead) then Sparce := 1 else Sparce := 0;
            FSout.WriteByte(Sparce);                                    // write out sparce indicator
            if Sparce = 0 then FSout.Write(Buff[0], NrBytesRead);       // only write out non-sparce block

            if SP.AppOptions.Verbose then PctProgress(BlockNr, Header.NrBlocks-1);

        end;

        // Read and write the final (possibly partial) block
        NrBytesRead := FSin.Read(Buff[0], Header.LastBlock);
        MD5Update(MD5Context, Buff[0], NrBytesRead);

        if NrBytesRead > 0 then begin

            if IsZeroBlock(Buff, NrBytesRead) then Sparce := 1 else Sparce := 0;
            FSout.WriteByte(Sparce);
            if Sparce = 0 then FSout.Write(Buff[0], NrBytesRead);
        end;

        // done writing out --> update hash in header --> overwrite headers in file and their CRCs
        MD5Final(MD5Context, Hash);
        Header.MD5Hash := Hash;
        FSout.Seek(0, soBeginning);

        CRC := crc32(0, nil, 0);                   // reset CRC
        CRC := crc32(CRC, @Header, SizeOf(Header)); // calc header CRC

        FSout.WriteBuffer(Header, SizeOf(Header)); // write out header with actual hash
        FSout.WriteBuffer(CRC, SizeOf(CRC));       // and write out CRC
        FSout.WriteBuffer(Header, SizeOf(Header)); // write out duplicate header with actual hash
        FSout.WriteBuffer(CRC, SizeOf(CRC));       // and write out duplicate header CRC

        if SP.AppOptions.Verbose then WriteLn;

        PackedSize := FSout.Size;
        if SP.AppOptions.Verbose then WriteLn('* Compression achieved: ',
                                              PackedSize*100 div Header.OrgSize, '% (-',
                                              100-PackedSize*100 div Header.OrgSize,'%)');

    end; // with SP

end;


// --- exposed unpack routines ----------------------

procedure ProbeUnpackInfile(var SP : TSparsePacker);
var
    Size : Int64 = 0;
    Magic : array[0..Length(PACKMAGIC)-1] of Byte;
    InFileName : String;
    S : String;
    i : Integer;
    HeaderError : Boolean;
    Header1, HEader2 : THeader;
    CRC1, CRC2, CRCcalc1, CRCcalc2 : Cardinal;
begin
    with SP do begin
        InFileName := AppOptions.InputFile;
        if SP.AppOptions.Verbose then WriteLn('* Probing: '+InFileName+' ...');

        FSin := nil;

        FSin := TFileStream.Create(InFileName, fmOpenRead or fmShareDenyWrite);
        Size := FSin.Size;
        if Size = 0 then begin
            Raise Exception.Create('Empty file "'+InFileName+'": Nothing to unpack');
        end;

        // check magic file marker
        FSin.ReadBuffer(Magic, SizeOf(Magic));
        S := '';
        for i := 0 to Length(PACKMAGIC)-1 do S := S + Chr(Magic[i]);
        if S <> PACKMAGIC then begin
            Raise Exception.Create('"'+InFileName+'": Not a SparcePacked file');
        end;

        // reset file pointer
        FSin.Seek(0, soBeginning);
        // read headers and CRCs
        FSin.ReadBuffer(Header1, SizeOf(Header1));
        FSin.ReadBuffer(CRC1, SizeOf(CRC1));
        FSin.ReadBuffer(Header2, SizeOf(Header2));
        FSin.ReadBuffer(CRC2, SizeOf(CRC2));
        // Check CRCs
        CRCcalc1 := crc32(0, nil, 0);
        CRCcalc1 := crc32(CRCcalc1, @Header1, SizeOf(Header1));
        CRCcalc2 := crc32(0, nil, 0);
        CRCcalc2 := crc32(CRCcalc2, @Header2, SizeOf(Header2));
        Header := Header1;
        if (CRCcalc1 <> CRC1 ) then begin
            WriteLn('Error: Corrupt file header, tryin to recover...');
            Header := Header2; // Use duplicate header
            if (CRCcalc2 <> CRC2 ) then Raise Exception.Create('Fatal error: unable to recover file header.');
            WriteLn('File header recovery Successfully.');
        end;

        // some header sanity checks
        HeaderError := False;
        with SP.Header do begin
            if (OrgSize <= 0) or (BlockSize <= 0) or (NrBlocks <= 0) or (LastBlock <= 0) then HeaderError := True;
            if (BlockSize > MAXBLKSIZE) or (BlockSize < MINBLKSIZE) then HeaderError := True;
            if Orgsize <> BlockSize*(NrBlocks-1) + LastBlock then HeaderError := True;
            if (BlockSize > OrgSize) and (LastBlock <> OrgSize ) then HeaderError := True;
            if CheckHash(MD5Hash, DummyMD5Hash) then HeaderError := True;
        end;
        if HeaderError then begin
            Raise Exception.Create('Error: Corrupt file header.');
        end;

        {$IFDEF DEBUG}
        if SP.AppOptions.Verbose then PrintHeader(SP);
        {$ENDIF}
    end; // with

end;


procedure SppUnpack(var SP : TSparsePacker; NoWrite : Boolean);
var
    BlockNr : Int64;
    BlockDataSize : LongWord;
    Sparce : Byte;
    NrBytesRead : Int64;
    MD5Context : TMD5Context;
    Hash : TMD5Digest;
begin
    BlockNr := 0;
    with SP do begin

        if AppOptions.Verbose then begin
            if NoWrite then
                Write('* Running check on: '+AppOptions.InputFile+': ')
            else
                Write('* Unpacking: '+AppOptions.InputFile+': ');
        end;

        MD5Init(MD5Context);

        repeat
            NrBytesRead := FSin.Read(Sparce, SizeOf(Sparce));
            if NrBytesRead = 0 then begin
                raise Exception.Create('Error unpacking -- file truncated file during reading '+SP.AppOptions.InputFile);
            end;

            // The last block may be shorter than BlockSize; every other block is full-size.
            if BlockNr = Header.NrBlocks - 1 then
                BlockDataSize := Header.LastBlock
            else
                BlockDataSize := Header.BlockSize;

            if Sparce = 0 then begin
                // write non-sparce block
                NrBytesRead := FSin.Read(Buff[0], BlockDataSize);
                if NrBytesRead = 0 then break;
                if (NoWrite = False) then FSout.Write(Buff[0], NrBytesRead);
                MD5Update(MD5Context, Buff[0], NrBytesRead);
            end
            else begin
                // write sparce block, using the correct size for the last block
                if (NoWrite = False) then FSout.Write(ZeroBuff[0], BlockDataSize);
                MD5Update(MD5Context, ZeroBuff[0], BlockDataSize);
            end;

            Inc(BlockNr);

            if AppOptions.Verbose then PctProgress(BlockNr, Header.NrBlocks);

        until BlockNr = Header.NrBlocks;

        if AppOptions.Verbose then WriteLn;

        MD5Final(MD5Context, Hash);

        if CheckHash(Hash, Header.MD5Hash) then begin
            if AppOptions.Verbose and (NoWrite = True)  then WriteLn('* Check successful');
            if AppOptions.Verbose and (NoWrite = False) then WriteLn('* Successfully unpacked '+AppOptions.InputFile+' --> '+AppOptions.OutputFile);
        end
        else begin
            WriteLn('!!! Error unpacking '+AppOptions.OutputFile+'. Original content not recovered !!!');
            Halt(1);
        end;

    end; // with SP

end;

begin
end.
