; 1 tab = 4 spaces

;
; This is a rewrite of Marco van Zwetselaar's USE!UMBS.SYS v2.0 from 1991.
;
; Changes in this version (v2.2);
; * UMBs are now initialized to avoid parity errors.
; * Minor size optimizations.
;
; Changes in the previous version (v2.1);
; * This file assembles in NASM.
; * Optimizations to reduce memory usage.
; * Command line parameters are now used in CONFIG.SYS to specify address ranges for UMBs.
;
;   Example for a single 128 KB UMB starting at segment D000h:
;
;   DEVICE=USE!UMBS.SYS D000-F000
;
; Please report bugs to me at krille_n_@hotmail.com
;
; Thanks!
;
; Krister Nordvall
;


;--------------------------------------------------------------------
; Skips the immediately following 2 byte instruction by using it
; as an immediate value to a dummy instruction.
; Destroys the contents of %1.
;
; SKIP2B
;	Parameters:
;		%1:		Any 16 bit general purpose register or F for flags.
;	Returns:
;		Nothing
;	Corrupts registers:
;		%1
;--------------------------------------------------------------------
%macro SKIP2B 1
	%ifidni		%1, f
		db	03Dh					; Opcode byte for CMP AX, <immed>
		;db	0A9h					; Alt. version TEST AX, <immed>
	%elifidni	%1, ax
		db	0B8h					; Opcode byte for MOV AX, <immed>
	%elifidni	%1, cx
		db	0B9h					; Opcode byte for MOV CX, <immed>
	%elifidni	%1, dx
		db	0BAh					; Opcode byte for MOV DX, <immed>
	%elifidni	%1, bx
		db	0BBh					; Opcode byte for MOV BX, <immed>
	%elifidni	%1, sp
		db	0BCh					; Opcode byte for MOV SP, <immed>
	%elifidni	%1, bp
		db	0BDh					; Opcode byte for MOV BP, <immed>
	%elifidni	%1, si
		db	0BEh					; Opcode byte for MOV SI, <immed>
	%elifidni	%1, di
		db	0BFh					; Opcode byte for MOV DI, <immed>
	%else
		%error "Invalid parameter passed to SKIP2B"
	%endif
%endmacro

		TAB						equ		9
		CR						equ		13
		SPACE					equ		32

		bRH_Command				equ		2
		wRH_Status				equ		3
		fpRH_BreakAddress		equ		14
		fpRH_CommandLine		equ		18


;--------------------------------------------
; The driverheader
		org 0
; any device driver will start with the following info:

		fpNextDeviceDriver		dd		-1
		wDeviceAttributeWord	dw		0E000h
		wOffsetStrategyRoutine	dw		StrategyRoutine
		wOffsetInterruptRoutine	dw		InterruptRoutine
		sDeviceName				db		'ZwetsUMB'

		fpRequestHeader			dd		0

;-------------------------------------------------------
; This is the code that is chained to the front of interrupt 2f.
; It will handle requests nrs. 4300 and 4310, and leave all others
;    to the existing code.

;INT 2F - EXTENDED MEMORY SPECIFICATION (XMS) v2+ - INSTALLATION CHECK
;	AX = 4300h
;Return: AL = 80h XMS driver installed
;	AL <> 80h no driver
;Notes:	XMS gives access to extended memory and noncontiguous/nonEMS memory
;	  above 640K
;	AX = 4310h
;Return: ES:BX -> driver entry point (see #02749,#02750,#02753,#02760,#02769,#02774)
;Notes:	HIMEM.SYS v2.77 chains to previous handler if AH is not 00h or 10h
;	    HIMEM.SYS requires at least 256 bytes free stack space when calling the driver entry point

Interrupt2FhHandler:
		cmp		ah, 43h
		je		SHORT RequestIsForMe

		db		0EAh					; Far jump opcode
fpOldInterrupt2FhHandler:
		dd		0						; Pointer filled in during initialization

RequestIsForMe:
		cmp		al, 10h
		jne		SHORT ReturnHandlerExists

		mov		bx, UMBController
		push	cs
		pop		es
		iret

ReturnHandlerExists:
		mov		al, 80h
		iret

;--------------------------------------------
; Strategy: store pointer to Request Header:
StrategyRoutine:
		mov		[cs:fpRequestHeader], bx
		mov		[cs:fpRequestHeader+2], es
		retf

;--------------------------------------------
; Interrupt: The routine that fires the install request

; Remember that the device will only answer the init-request
; which is called by dos as it installs the driver.
; Any later calls will be ignored - they are not needed anyway.
InterruptRoutine:
		push	es
		push	bx
		push	ax

		les		bx, [cs:fpRequestHeader]
		mov		al, [es:bx+bRH_Command]
		test	al, al
		jz		SHORT Install

		cmp		al, 10h
		jbe		SHORT .NotImplemented
		mov		ax, 8003h				; "Unknown command"
		SKIP2B	f
.NotImplemented:
		xor		ax, ax

Return:
		or		ax, 100h				; Set Done bit
		mov		[es:bx+wRH_Status], ax

		pop		ax
		pop		bx
		pop		es
		retf

;------------------------------------------------------
; This is the small XMS manager that we install. It will only react
; to requests for UMBs (so when AH=10h). If not, it *should* pass
; control to the existing XMS manager - provided there is one. Or
; otherwise inform the caller that there is no eXt memory.

;Format of XMS driver entry point:
;Offset	Size	Description	(Table 02749)
; 00h  5 BYTEs	jump to actual handler
;		either short jump (EBh XXh) followed by three NOPs or
;		  far jump (EAh XXXX:XXXX) to a program which has hooked itself
;		  into the XMS driver chain
;Note:	to hook into the XMS driver chain, a program should follow the chain of
;	  far jumps until it reaches the short jump of the driver at the end
;	  of the chain; this short jump is to be replaced with a far jump to
;	  the new handler's entry point, which should contain a short jump
;	  followed by three NOPs.  The new handler must return to the address
;	  pointed at by the short jump which was overwritten.  Using this
;	  method, the new handler becomes the first to see every XMS request.

UMBController:
; The first 5 bytes of Himem handlers are special and must not be changed.
		jmp		SHORT .CheckIfUMBorXMSrequest
		nop
		nop
		nop

.CheckIfUMBorXMSrequest:
		cmp		ah, 10h                 ;is it a UMB request?  Accept only the fonction 10h : Request UMB 
		je		SHORT UMBrequest

JMPtoOurXMShandler:
		jmp		SHORT XMSrequest		; This jump is patched out during init if an existing XMS handler is detected
fpOldXMShandler	equ	JMPtoOurXMShandler+1
		db		0
		db		0
		db		0

;Call the XMS driver "Request upper memory block" function with:
;	AH = 10h
;	DX = size of block in paragraphs
;Return: AX = status
;	    0001h success
;		BX = segment address of UMB
;		DX = actual size of block
;	    0000h failure
;		BL = error code (80h,B0h,B1h) (see #02775)
;		DX = largest available block
;Notes:	Upper Memory consists of non-EMS memory between 640K and 1024K
;	the XMS driver need not implement functions 10h through 12h to be
;	  considered compliant with the standard
;	under DOS 5+, if CONFIG.SYS contains the line DOS=UMB, then no upper
;	  memory blocks will be available for allocation because all blocks
;	  have been grabbed by MS-DOS while booting

;Call the XMS driver "Release upper memory block" function with:
;	AH = 11h
;	DX = segment address of UMB to release
;Return: AX = status
;	    0001h success
;	    0000h failure
;		BL = error code (80h,B2h) (see #02775)
;Note:	the XMS driver need not implement functions 10h through 12h to be
;	  considered compliant with the standard


UMBrequest:
		push	si
		push	cx
		push	bx

		SKIP2B	si
.wOffsetFreeUMBs:
		dw		0						; Offset filled in during init

		xor		cx, cx
		xchg	dx, cx					; DX = 0, CX = Requested block size

.Search:
		cs
		lodsw							; Load start address of range
		test	ax, ax					; Are we at the end of the list?
		jz		SHORT .NoBlockFound		; Jump if so
		mov		bx, ax					; Segment is returned in BX
		inc		ax						; Block already given away?
		cs
		lodsw							; Load length of block
		jz		SHORT .Search			; If yes, get next block
		cmp		dx, ax					; Is it larger than the largest found so far?
		ja		SHORT .CheckSize		; If not, check size to see if it's large enough
		mov		dx, ax					; It is so save it as the largest so far

.CheckSize:
		cmp		cx, ax					; Large enough to fulfill request?
		ja		SHORT .Search			; Jump if not

		mov		WORD [cs:si-4], 0FFFFh	; Mark as given away
		mov		dx, 1					; Return Success in AX and size of block in DX
		xchg	dx, ax
		pop		cx						; Remove BX from stack
		jmp		SHORT .Return

.NoBlockFound:
		pop		bx						; Restore BX
		mov		bl, 0B0h				; Return "Smaller UMB available" in BL
		test	dx, dx					; Size of largest block found = 0?
		jnz		SHORT .Return			; If not, assumption was correct
		inc		bx						; Yes, return "No UMBs available" instead

.Return:
		pop		cx
		pop		si
		retf

; Below is the code that will respond to non-UMB (and thus XMS-)
; requests when no XMS-manager is present. To nearly all requests
; (there are 11h) it will answer with AX=0000, meaning failure
; and BL=80, which gives the errormessage: not implemented.
; Only fns 00h and 08h are treated specially (as well as fn 10h, but
; that has been filtered out above - it's the UMB-request).
XMSrequest:
		test	ah, ah					; Get XMS version?
		jnz		SHORT .NotGetVersion

		xor		bx, bx					; Internal revision number
		cwd								; HMA not present
		jmp		SHORT .Return

.NotGetVersion:
		cmp		ah, 8					; Query extended memory?
		jne		SHORT .NotQueryExtendedMem
		cwd								; 0 KB extended memory

.NotQueryExtendedMem:
		mov		bl, 80h					; Error: Not implemented

.Return:
		xor		ax, ax					; Always return failure
		retf

;=================================================================
;
; NON-RESIDENT PART
;
; The part that follows now will not remain resident. It will be
; executed only once: at the time the driver is installed by
; DOS' bootprocedures.
;
; This code takes care of (1) hooking our intercepting code to
; int 2f, (2) hooking our small XMS-manager to the already installed
; one - provided there is one, (3) and if not, installing the
; the response-robot that will inform callers that there's no eXt
; memory.
;

;-------------------------------------------------------
; Installation routine. Called once.

Install:
		push	cx
		push	dx
		push	ds
		push	si

		push	cs
		pop		ds

		mov		ah, 9
		mov		dx, s$Hello1
		int		21h
		mov		dx, s$Hello2
		int		21h
		mov		dx, s$Empty
		int		21h
		mov		dx, s$Hello3
		int		21h
		mov		dx, s$Empty
		int		21h
		mov		dx, s$Author
		int		21h
		mov		dx, s$Empty
		int		21h

		; Is there an XMS handler already?
		mov		ax, 4300h
		int		2Fh
		cmp		al, 80h
		jne		SHORT .OKtoInstall		; No, it's OK to install (with our handler)

		; Yes, patch out the short unconditional jump to our XMS handler
		mov		BYTE [JMPtoOurXMShandler], 0EAh		; 'jmp far ...'

		; Then get the address to the old handler and store it
		mov		ax, 4310h
		int		2Fh
		mov		[fpOldXMShandler], bx
		mov		[fpOldXMShandler+2], es

		; To reduce memory usage we also move the breakpoint to exclude our XMS handler
		mov		WORD [.wOffsetBreakpoint], XMSrequest

		; Tell the user we found an existing handler
		mov		ah, 9
		mov		dx, s$XMMfound
		int		21h
		mov		dx, s$Empty
		int		21h

		; Check if it services UMBs by trying to allocate far too much
		mov		ah, 10h
		cwd
		dec		dx
		call	FAR [fpOldXMShandler]

		; Assume we are not needed
		mov		dx, s$NotInstalled
		xor		ax, ax

		cmp		bl, 80h					; Error: Not implemented?
		je		SHORT .OKtoInstall
		jmp		.StoreBreakPointer

.OKtoInstall:
		; Get the breakpoint (Install or XMSrequest) to BX and store it as the start of the FreeUMBs list
		mov		bx, [.wOffsetBreakpoint]
		mov		[UMBrequest.wOffsetFreeUMBs], bx

		; Time to interpret the command line in CONFIG.SYS
		lds		si, [fpRequestHeader]
		lds		si, [si+fpRH_CommandLine]

		push	cs						; For restoring DS later

		mov		cx, 4					; Hex digit count in CH = 0, Shift count in CL = 4
		xor		ah, ah					; WORD parameter count in AH
		; First scan until we find a whitespace (tab or space) to find the start of parameters
.SearchForWhiteSpace:
		lodsb
		cmp		al, CR
		je		SHORT .EndOfLineEncountered
		cmp		al, SPACE
		je		SHORT .SearchForParameter
		cmp		al, TAB
		jne		SHORT .SearchForWhiteSpace

		; We've found the first whitespace which means we've reached the end of the path+filename
.SearchForParameter:
		lodsb
		cmp		al, CR
		je		SHORT .EndOfLineEncountered
		cmp		al, SPACE
		je		SHORT .SearchForParameter
		cmp		al, TAB
		je		SHORT .SearchForParameter

		; We have the first byte of a parameter
		dec		si
.NextHexDigit:
		lodsb
		inc		ch
		cmp		al, '9'
		jbe		SHORT .NotAtoF
		and		al, ~32
		cmp		al, 'F'
		ja		SHORT .ParameterError
		cmp		al, 'A'
		jb		SHORT .ParameterError
		sub		al, 7
.NotAtoF:
		sub		al, '0'
		jb		SHORT .ParameterError
		shl		dx, cl
		or		dl, al
		and		ch, 3
		jnz		SHORT .NextHexDigit

		; We have a complete WORD in DX
		inc		ah						; Increment WORD count
		sahf							; WORD count Odd or Even?
		jc		SHORT .FirstWordOfParameter
		sub		dx, [cs:bx-2]			; Convert end of range to length
		jbe		SHORT .ParameterError	; End of range below or equal to start of range
.FirstWordOfParameter:
		mov		[cs:bx], dx
		inc		bx
		inc		bx
		lodsb
		sahf
		jc		SHORT .CheckIfDash
		cmp		al, CR
		je		SHORT .EndOfLineEncountered
		cmp		al, SPACE
		je		SHORT .SearchForParameter
		cmp		al, TAB
		je		SHORT .SearchForParameter
		SKIP2B	ax						; Fall through to .ParameterError
.CheckIfDash:
		cmp		al, '-'
		je		SHORT .NextHexDigit

.ParameterError:
		pop		ds						; DS = CS

		mov		dx, s$ParamError
		xor		ax, ax
		jmp		SHORT .StoreBreakPointer

.EndOfLineEncountered:
		test	ah, ah
		jz		SHORT .ParameterError	; No parameters at all

		pop		ds						; DS = CS

		mov		WORD [bx], 0			; End of Free UMBs block marker
		inc		bx
		inc		bx
		mov		[.wOffsetBreakpoint], bx

		; We need to initialize the UMBs by writing to every address to avoid parity errors later when reading
		mov		si, [UMBrequest.wOffsetFreeUMBs]
		push	di

.InitNextBlock:
		lodsw							; Segment address of UMB to AX
		test	ax, ax
		jz		SHORT .AllBlocksInitialized
		xchg	bx, ax					; Save address in BX
		lodsw							; Block size in paragraphs to AX
		xor		dx, dx
		xchg	dx, ax					; DX = Paragraph count, AX = Zero
		xor		di, di					; Point ES:DI to start of UMB
.InitNextSegment:
		mov		es, bx
		cmp		dh, 10h					; Block larger than or equal to a full segment?
		jb		SHORT .LessThan64KB
		mov		cx, 8000h				; We need to write (at least) a full 64 KB segment
		add		bh, 10h					; Add 64 KB to the segment address for the next iteration (if any)
		sub		dh, 10h					; Subtract 64 KB from the paragraph count
		rep		stosw
		jmp		SHORT .InitNextSegment
.LessThan64KB:
		mov		cl, 3
		shl		dx, cl					; Paragraphs to WORDs
		mov		cx, dx					; WORD count to CX
		rep		stosw
		jmp		SHORT .InitNextBlock

.AllBlocksInitialized:
		pop		di

		; Get handler for Interrupt 2Fh and store it
		mov		ax, 352Fh
		int		21h
		mov		[fpOldInterrupt2FhHandler], bx
		mov		[fpOldInterrupt2FhHandler+2], es

		; Then hook it
		mov		ax, 252Fh
		mov		dx, Interrupt2FhHandler
		int		21h

		; Tell the user we are installed
		mov		dx, s$Installed
		SKIP2B	ax
.wOffsetBreakpoint:
		dw		Install					; Default breakpoint offset is Install

.StoreBreakPointer:
		les		bx, [fpRequestHeader]
		mov		[es:bx+fpRH_BreakAddress], ax
		mov		[es:bx+fpRH_BreakAddress+2], cs

		mov		ah, 9
		int		21h						; Print Installed/NotInstalled/ParamError

		xor		ax, ax					; No errors
		pop		si
		pop		ds
		pop		dx
		pop		cx
		jmp		Return


s$Hello1		db	0Dh,0Ah,'嬪様様様様様様裕   Use!UMBs   突様様様様様様�',0Dh,0Ah
s$Empty			db			'�                                           �',0Dh,0Ah,'$'
s$Hello2		db			'�        Upper Memory Block - Manager       �',0Dh,0Ah,'$'
s$Hello3		db			'�   Works on any PC/XT/AT, either with or   �',0Dh,0Ah
				db			'�    without Extended or Expanded Memory!   �',0Dh,0Ah,'$'
s$XMMfound		db			'�     * found extended memory manager *     �',0Dh,0Ah,'$'
s$Author		db			'�        Author: Marco van Zwetselaar       �',0Dh,0Ah
				db			'�   dedicated it to the Public Domain 1991  �',0Dh,0Ah,'$'
s$Installed		db			'塒裕 Version 2.2 突様様様様裕 Installed! 突余',0Dh,0Ah,0Ah,'$'
s$NotInstalled	db			'塒� Not Installed!  UMBs Managed Already! 突�',0Dh,0Ah,0Ah,'$'
s$ParamError	db			'塒� Not Installed!  Invalid Command Line! 突�',0Dh,0Ah,0Ah,'$'

