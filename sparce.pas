program SparcePack;

{$I compiler.inc}

uses
    Classes, SysUtils,
    Consts, SppUnit;

var
    SPP : TSparsePacker;

begin

    InitHeader(SPP);
    GetParams(SPP);
    if SPP.AppOptions.Verbose then WriteLn(PACKNAME, ' version ',PACKVER,'. ', PACKCR);
    try

        if SPP.AppOptions.Action = 'pack' then begin
            ProbePackInfile(SPP);
            InitBuff(SPP.Buff, SPP.Header.BlockSize);
            CreateOutFile(SPP);
            SppPack(SPP);
            if SPP.AppOptions.CheckPacked then begin
                // force OS to flush data to physical disk
                if not FileFlush(SPP.FSout.Handle) then
                    raise Exception.Create('fsync failed: ' + SysErrorMessage(GetLastOSError));
                // close the open streams
                if SPP.FSout <> nil then FreeAndNil(SPP.FSout);
                if SPP.FSin <> nil then FreeAndNil(SPP.FSin);
                // set the InputFile to the previously packed OutputFile and do an unpack without writing to file
                SPP.AppOptions.InputFile := SPP.AppOptions.OutputFile;
                ProbeUnpackInfile(SPP);
                InitBuff(SPP.Buff, SPP.Header.BlockSize);
                InitBuff(SPP.ZeroBuff, SPP.Header.BlockSize);
                SppUnpack(SPP, True);
            end;
        end
        else begin
            ProbeUnpackInfile(SPP);
            InitBuff(SPP.Buff, SPP.Header.BlockSize);
            InitBuff(SPP.ZeroBuff, SPP.Header.BlockSize);
            CreateOutFile(SPP);
            SppUnpack(SPP, False);
        end;

    except

        on E: Exception do begin
            Writeln(E.ClassName, ': ', E.Message);
            Halt(1);
        end;

    end; // try

    // and clean up streams
    if SPP.FSout <> nil then begin
        // force OS to flush data to physical disk
        if not FileFlush(SPP.FSout.Handle) then
            raise Exception.Create('fsync failed: ' + SysErrorMessage(GetLastOSError));
        FreeAndNil(SPP.FSout);
    end;
    if SPP.FSin  <> nil then FreeAndNil(SPP.FSin);
    if SPP.AppOptions.Verbose then WriteLn('Done.');
end.
