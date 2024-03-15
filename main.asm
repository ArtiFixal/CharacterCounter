.586
.MODEL flat, STDCALL

includelib .\lib\fpu.lib

;__UNICODE__				equ 1
STD_INPUT_HANDLE		equ -10
STD_OUTPUT_HANDLE		equ -11

SRC1_REAL	equ		2
SRC2_DIMM   EQU		2048

GENERIC_READ			equ 80000000h
GENERIC_WRITE			equ 40000000h
CREATE_ALWAYS			equ 2
OPEN_EXISTING			equ 3
FILE_SHARE_READ			equ 1h
FILE_ATTRIBUTE_NORMAL	equ 80h
FILE_ATTRIBUTE_READONLY	equ 1h
; Error code returned by CreateFile with dwCreationDisposition 
; set to CREATE_ALWAYS or OPEN_EXISTING is set when file already exists
ERROR_ALREADY_EXISTS equ 183

; Unicode support
IFDEF __UNICODE__
	GetCommandLine equ <GetCommandLineW>
	ReadConsole equ <ReadConsoleW>
	WriteConsole equ <WriteConsoleW>
	wsprintf equ <wsprintfW>
	PathFileExists equ <PathFileExistsW>
	PathRemoveExtension equ <PathRemoveExtensionW>
	CreateFile equ <CreateFileW>
	lstrlen	equ	<lstrlenW>
	lstrcat equ <lstrcatW>
	TCHAR					typedef WORD
	CHAR_REG equ <ax>
; ANSI support
ELSE
	GetCommandLine equ <GetCommandLineA>
	ReadConsole equ <ReadConsoleA>
	WriteConsole equ <WriteConsoleA>
	wsprintf equ <wsprintfA>
	PathFileExists equ <PathFileExistsA>
	PathRemoveExtension equ <PathRemoveExtensionA>
	CreateFile equ <CreateFileA>
	lstrlen	equ	<lstrlenA>
	lstrcat equ <lstrcatA>
    TCHAR					typedef BYTE
	CHAR_REG equ <al>
ENDIF

; type defs
WINAPI						typedef PROTO STDCALL
bool                        typedef BYTE
BOOLEAN                     typedef BYTE
CHAR                        typedef BYTE
UCHAR                       typedef BYTE
USHORT                      typedef WORD
ATOM                        typedef WORD
WCHAR                       typedef WORD
FILEOP_FLAGS                typedef WORD
HANDLE						typedef DWORD
LPVOID						typedef DWORD
LPDWORD						typedef DWORD
LPSTR						typedef DWORD

; function protorypes
GetStdHandle PROTO stdHandleConst:DWORD
ReadConsole PROTO consoleInHandle:HANDLE, bufferToReadInto:LPVOID, numberOfCharsToRead:DWORD, charsRead:LPDWORD, inputControl:LPVOID
GetCommandLine PROTO
CommandLineToArgvW PROTO cmdLine:LPSTR, argsNum:LPVOID
LocalFree PROTO :DWORD
WriteConsole PROTO consoleOutHandle:HANDLE, bufferToWriteFrom:LPVOID, numberOfCharsToWrite:DWORD, charsWritten:LPDWORD, reserved:LPVOID
wsprintf PROTO C destination:LPSTR,format:LPSTR,args:VARARG
GetCurrentDirectory PROTO :DWORD,:LPSTR
PathFileExists PROTO STDCALL :DWORD
PathRemoveExtension PROTO :LPSTR
CreateFile PROTO fileName:LPSTR, desiredAccess:DWORD, sharedMode:DWORD, securityAttributes:DWORD, creationDisposition:DWORD,
	flagsAndAttributes:DWORD, templateFile:HANDLE
WriteFile PROTO fileHandle:HANDLE, bufferToWriteFrom:LPVOID, numberOfBytesToWrite:DWORD, numberOfBytesWritten:LPDWORD, overlapped:DWORD
ReadFile PROTO fileHandle:HANDLE, bufferToReadInto:LPVOID, numberOfBytesToRead:DWORD, numberOfBytesRead:LPDWORD, overlapped:DWORD
CloseHandle PROTO :HANDLE
lstrlen PROTO :LPSTR
lstrcat PROTO destination:LPSTR, source:LPSTR
GetLastError PROTO
ExitProcess PROTO :DWORD
FpuFLtoA PROTO source:DWORD,decimalPrecision:DWORD,destination:DWORD,uID:DWORD
; To convert ANSI float into WCHAR
IFDEF __UNICODE__
	GetConsoleCP PROTO
	MultiByteToWideChar PROTO :DWORD,:DWORD,:LPSTR,:DWORD,:LPSTR,:DWORD
ENDIF

;
; Macro used to define strings. When __UNICODE__ is defined identifies 
; string as UNICODE, otherwise identifies string as ANSI.
;
; varname - name by which string will be accessible
; str - string which will be defined
; crlf - should \r\n should be included at the end?
;
; Usage:
; text <nameOfVar>,"text to define"
;
; Result:
; nameOfVar "defined text in ANSI/WCHAR"
;
text macro varname:REQ,str:REQ,crlf
	IFDEF __UNICODE__
	isNameDefined equ <0>
	.data
		FORC char,<str>
			IFDIF <char>,<">			;" - highlight fix
				IFE isNameDefined
					varname TCHAR "&char"
					isNameDefined equ <1>
				ELSE
					TCHAR "&char"
				ENDIF
			ENDIF
		endm
	ELSE
		varname TCHAR str
	ENDIF
	; If defined add CLRF at the end
	IFNB <crlf>
		TCHAR 13,10
	ENDIF
	; End string with '/0'
	TCHAR 0
endm

_DATA SEGMENT
	consoleOut			HANDLE	?
	consoleIn			HANDLE	?

	text				<enterFile>,"Enter path to a file: "
	enterFileSize		DD		($ - enterFile)/TYPE enterFile
	text				<fileNotFound>,"File at given path doesn't exist.",1
	fileNotFoundSize	DD		($ - fileNotFound)/TYPE fileNotFound
	chOut				DD		?
	filePath			TCHAR	256 dup(0)
	; Array containing number of character occurrences where index corresponds to its character
	; Ex. 65 = A
	countArr			DD		65536 dup(0)
	readBuff			TCHAR	512 dup(0)
	charsRead			DD		0
	totalFileChars		DD		0
	text				<resultFileSuffix>,"-result.txt"
	; UTF-16LE BOM
	bom					DB		0ffh,0feh,0
	; Format in which result row will be displayed
	text				<resultFormat>,"Char: %c count: %ld (%s)",1
	text				<totalFormat>,"Total characters: %ld",1
	; Buffer used to format result string
	resultBuff			TCHAR	90 dup(0)
	numberCount			DD		?
	percentage			REAL10	?
	fpuBuff				DB		16 dup(0)
	fpuPrecision		DD		2
	hundred				DD		100
	text				<errorMsg>,"An error occured. Error code: %ld",1
	errorBuf			TCHAR	44 dup(0)

	IFDEF __UNICODE__
		codepage	DD		?
		uniBuff		TCHAR	16 dup(0)
	ENDIF

_DATA ENDS
_TEXT SEGMENT

main PROC
	IFDEF __UNICODE__
		call GetConsoleCP
		mov codepage,eax
	ENDIF

	; Get console handles
	push STD_OUTPUT_HANDLE
	call GetStdHandle
	mov consoleOut, EAX

	push STD_INPUT_HANDLE
	call GetStdHandle
	mov consoleIn, EAX

	push 0
	push offset chOut
	push enterFileSize
	push offset enterFile
	push consoleOut
	call WriteConsole

	push 0
	push OFFSET charsRead
	push SIZEOF filePath
	push OFFSET filePath
	push consoleIn
	call ReadConsole

	mov ebx, OFFSET filePath
	mov eax,charsRead
	call StripCRLF
	push OFFSET filePath
	call PathFileExists
	cmp eax,0
	je noFile

	mov eax,OFFSET filePath
	call countCharacters
	jmp foundFile
noFile:
	
	push 0
	push offset chOut
	push fileNotFoundSize
	push offset fileNotFound
	push consoleOut
	call WriteConsole

foundFile:

	push consoleOut
	call CloseHandle
	push consoleIn
	call CloseHandle

	push 0
	call ExitProcess
main ENDP

;
; Counts characters in a file.
;
; eax - Path to a file to read from.
;
countCharacters PROC
	LOCAL fileHandle :HANDLE

	; Total character count
	xor ebx,ebx

	push 0
	push FILE_ATTRIBUTE_NORMAL
	push OPEN_EXISTING
	push 0
	push FILE_SHARE_READ
	push GENERIC_READ
	push eax
	call CreateFile

	mov fileHandle,eax
	call GetLastError
	cmp eax,0
	jne error
	
readLoop:
	push 0
	push OFFSET charsRead
	push SIZEOF readBuff
	push OFFSET readBuff
	push fileHandle
	call ReadFile
	mov ecx,charsRead
	; inc totalCharacterRead
	add ebx,ecx
	; zero eax to avoid arrayOutOfBounds
	xor eax,eax
count:
	mov CHAR_REG,[readBuff+ecx-TYPE TCHAR]
	; Since wchar is 2 byte dec by 1
	IFDEF __UNICODE__
		dec ecx
	ENDIF
	; Increment character occurrence in array at character index
	inc [countArr+eax*TYPE countArr]
	loop count
	; Read until EOF
	cmp charsRead,SIZEOF readBuff
	je readLoop
	push fileHandle
	call CloseHandle
	jmp countEnd
error:
	call printError
	jmp errorEnd
countEnd:
	mov totalFileChars,ebx
	call saveResults
errorEnd:
	ret
countCharacters ENDP

;
; Saves character occurence results to a file.
;
saveResults PROC
	LOCAL resultHandle :HANDLE
	; Strip extension
	push OFFSET filePath
	call PathRemoveExtension

	; Add result suffix to the file containing count results
	push OFFSET resultFileSuffix
	push OFFSET filePath
	call lstrcat
	
	push 0
	push FILE_ATTRIBUTE_NORMAL
	push CREATE_ALWAYS
	push 0
	push 0
	push GENERIC_WRITE
	push OFFSET filePath
	call CreateFile
	mov resultHandle,eax
	call GetLastError
	cmp eax,ERROR_ALREADY_EXISTS
	je overwrite
	; Bitwise check if there is no error (eax is 0)
	test eax,eax
	jnz error

overwrite:
	IFDEF __UNICODE__
		mov eax,totalFileChars
		mov ebx,TYPE TCHAR
		div ebx
		mov totalFileChars,eax

		push 0
		push 0
		push 2
		push OFFSET bom
		push resultHandle
		call WriteFile
	ENDIF
	; Zero array index register
	xor ebx,ebx
writeLoop:
	mov eax,[countArr+ebx*TYPE countArr]
	; Save only characters which occurr
	; Bitwise check for 0
	test eax,eax
	jz nextResult

	; Calc character occurrence percentage
	mov numberCount,eax
	fild numberCount
	fild totalFileChars
	fdivp
	fild hundred
	fmulp
	fstp percentage

	; Convert float to ANSI
	push SRC1_REAL or SRC2_DIMM
	push OFFSET fpuBuff
	push fpuPrecision
	push OFFSET percentage
	call FpuFLtoA
	
	IFDEF __UNICODE__
		push 16
		push OFFSET uniBuff
		push -1
		push OFFSET fpuBuff
		push 0
		push codepage
		call MultiByteToWideChar
	ENDIF
	
	IFDEF __UNICODE__
		; wchar buffer
		push OFFSET uniBuff
	ELSE
		; ANSI buffer
		push OFFSET fpuBuff
	ENDIF
	push numberCount
	push ebx
	push OFFSET resultFormat
	push OFFSET resultBuff
	call wsprintf
	; Correct stack pointer after wsprintf
	add	esp,20

	IFDEF __UNICODE__
		; Since wchar is 2 byte and wsprintf returns formated string length,
		; multiply eax by its type to match UNICODE resultBuff size
		imul eax,TYPE TCHAR
	ENDIF

	push 0
	push 0
	push eax
	push OFFSET resultBuff
	push resultHandle
	call WriteFile

nextResult:
	inc ebx
	cmp ebx,LENGTHOF countArr
	jne writeLoop
	jmp endWrite
error:
	call printError
	jmp endError
endWrite:

	push totalFileChars
	push OFFSET totalFormat
	push OFFSET resultBuff
	call wsprintf
	add esp,12

	IFDEF __UNICODE__
		; Calc wchar buff size
		imul eax,TYPE TCHAR
	ENDIF

	push 0
	push 0
	push eax
	push OFFSET resultBuff
	push resultHandle
	call WriteFile
	
	push resultHandle
	call CloseHandle
endError:
	ret
saveResults ENDP

;
; Prints occurred error to the console.
;
; eax - Error code.
;
printError PROC
	; Format string
	push eax
	push OFFSET errorMsg
	push OFFSET errorBuf
	call wsprintf
	add esp,12

	push 0
	push OFFSET chOut
	push eax
	push offset errorBuf
	push consoleOut
	call WriteConsole
	ret
printError ENDP

;
; Strips CRLF from string.
; 
; eax - string from which to strip.
;
StripCRLF proc
	IFDEF __UNICODE__
		imul eax,TYPE TCHAR
	ENDIF
	mov TCHAR PTR [ebx+eax-TYPE TCHAR],0
	mov TCHAR PTR [ebx+eax-(TYPE TCHAR*2)],0
    ret
StripCRLF endp
END