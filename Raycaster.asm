;-------------------------------------------------------------------------------------------------------------------
; Epic 3D Assembler in x86 ASM - (c) 2024 Aidan Tiruvan
;-------------------------------------------------------------------------------------------------------------------

.686p
.model flat,stdcall
option casemap:none

WinMain             proto   :DWORD,:DWORD,:DWORD,:DWORD

;MAIN

UpdateAndRender     proto   :DWORD, :DWORD
GetDt               proto
UpdateLogic         proto
Render              proto   :DWORD, :DWORD

InitMap             proto

;RENDER

RenderWallK         proto   :DWORD, :DWORD, :DWORD, :DWORD  ;hdcBack, h, x, color

RenderCoord         proto   :DWORD
TestRenderKeys      proto   :DWORD

;ENGINE

RayCastingEngine    proto   :DWORD
FindWallRayY        proto
FindWallRayX        proto


include \masm32\include\windows.inc
include \masm32\include\user32.inc
include \masm32\include\kernel32.inc
include \masm32\include\gdi32.inc
include \masm32\include\masm32.inc

include \masm32\include\winmm.inc       ;sound
includelib \masm32\lib\winmm.lib        ;sound

includelib \masm32\lib\user32.lib
includelib \masm32\lib\kernel32.lib
includelib \masm32\lib\gdi32.lib

includelib \masm32\lib\masm32.lib

include c:\masm32\macros\macros.asm

SCREEN_WIGTH    equ     1366    ;800       ;left, right
SCREEN_HEIGHT   equ     768     ;600       ;up, down      Don't different vertical and horizontal

RenderColorTest equ     255     ;16711680;65280

; Define floor and ceiling colors
FLOOR_COLOR     equ     00808080h  ; Greyish color for the floor
CEILING_COLOR   equ     00A0A0FFh  ; Light blue color for the ceiling (sky)

coordinate  struct

    X       dd  0.0     ;65x65
    Y       dd  0.0     ;65x65
    
    Angle   dd  0.0     ;0-> 2 Pi  (radian)

coordinate Ends

.data
    hInstance   HINSTANCE   ?
    CommandLine LPSTR       ?

    ClassName   db "WinClass",0
    GameName    db "ASM Game - Aidan Tiruvan",0    ;"Maze",0

    dtime       dd  32
    prevTime    dd  0

    turnConst   dd  0.0005  ;0.0004     ;coef
    moveConst   dd  0.002   ;0.001      ;coef

    WallConst   dd  700
    colorConst  dd  5   ;5 + need normal wall

    turnSign    dw  1       ;+1 = right, -1 = left

    player      coordinate  {30.0, 35.2, 1.58}

    key_state   db  0

    textkey_up      db ' up '
    textkey_down    db 'down'
    textkey_left    db 'left'
    textkey_right   db 'right'

    coordXe         db "X="
    coordYe         db "Y="
    coordAngle      db "Angle ="

    num180          dd  180
    num0dot5        dd  0.5

    RadianPerPixel  dd  0.0011

    bufb    db 10 dup(?)
    bufw    dw  ?
    bufd    dd  ?

    sound   db  'L.wav',0

    map     db  4225 dup(0)     ;65x65 - map

    dxLook      dd  0.0
    dyLook      dd  0.0
    bufAngle    dd  0.0

    bufX_dd dd  0.0
    bufY_dd dd  0.0

    bufX_dw dw  0
    bufY_dw dw  0

    epsilon     dd  0.001
    lookEpsilon dd  0.001  ;+- view, use look angle  

    lenWallY    dd  0
    lenWallX    dd  0

;.data?
.code
start:
    invoke GetModuleHandle, NULL ;return -> eax handle
    mov hInstance,eax 
    invoke GetCommandLine
    invoke WinMain, hInstance,NULL,CommandLine, SW_SHOWDEFAULT
    invoke ExitProcess,eax

WinMain proc hInst:HINSTANCE,hPrevInst:HINSTANCE,CmdLine:LPSTR,CmdShow:DWORD
    LOCAL   winclass:WNDCLASSEX
    LOCAL   msg:MSG
    LOCAL   hwnd:HWND

    LOCAL hdc       :HDC 
    LOCAL hdcBack   :HDC
    LOCAL memBitMap :HBITMAP

    LOCAL       md  :DEVMODE        ;Fullscreen (changemode)

    ;make winclass structure 
        mov winclass.cbSize,SIZEOF WNDCLASSEX
        mov winclass.style, CS_VREDRAW or CS_HREDRAW or CS_OWNDC
        mov winclass.lpfnWndProc, offset WinProc
        mov winclass.cbClsExtra,NULL
        mov winclass.cbWndExtra,NULL
        push hInst
        pop winclass.hInstance
        ;background <- GetStockObject(White_Brush), but const works too! 
        mov winclass.hbrBackground,15;NULL;15
        mov winclass.lpszMenuName,NULL
        mov winclass.lpszClassName,offset ClassName
        ;invoke LoadImage,hInst,addr GameIcon,IMAGE_ICON, NULL, NULL,LR_LOADFROMFILE; or LR_DEFAULTCOLOR
        invoke  LoadIcon,hInst,IDI_APPLICATION
        mov winclass.hIcon,eax
        mov winclass.hIconSm,eax
        invoke LoadCursor,NULL,IDC_ARROW
        mov winclass.hCursor,eax
    ;register Class!
        invoke RegisterClassEx,addr winclass
    ;create WINDOW!
        ;invoke CreateWindowEx,NULL,ADDR ClassName,ADDR GameName,WS_OVERLAPPEDWINDOW or WS_VISIBLE,BORDER_LEFT,BORDER_TOP,SCREEN_WIGTH,SCREEN_HEIGHT,NULL,NULL,hInst,NULL
        invoke CreateWindowEx,WS_EX_TOPMOST,ADDR ClassName,ADDR GameName,WS_POPUP,NULL,NULL,SCREEN_WIGTH,SCREEN_HEIGHT,NULL,NULL,hInst,NULL   
        mov hwnd,eax    ;handle
    ;make FULLSCREEN
        mov md.dmSize, sizeof md
        mov md.dmFields, DM_BITSPERPEL or DM_PELSWIDTH or DM_PELSHEIGHT
        mov md.dmPelsWidth, SCREEN_WIGTH;
        mov md.dmPelsHeight, SCREEN_HEIGHT;
        mov md.dmBitsPerPel, 32;
        invoke ChangeDisplaySettings, addr md, CDS_FULLSCREEN

        invoke ShowWindow, hwnd,SW_SHOWNORMAL
        invoke UpdateWindow, hwnd

        invoke ShowCursor,0

    ;SOUND
        invoke PlaySound,addr sound, NULL, SND_ASYNC or SND_LOOP
    ;Init map
        invoke InitMap
    ;DOUBLE BUFFERING
        invoke  GetDC,hwnd
        mov hdc, eax
        invoke CreateCompatibleDC,hdc
        mov hdcBack, eax
        invoke CreateCompatibleBitmap,hdc, SCREEN_WIGTH, SCREEN_HEIGHT
        mov memBitMap, eax
        invoke SelectObject,hdcBack, memBitMap


    ;MAIN EVENT CYCLE
        .WHILE TRUE
            invoke PeekMessage, ADDR msg,NULL,0,0,PM_REMOVE
            .BREAK .if (msg.message==WM_QUIT)
            invoke TranslateMessage, ADDR msg
            invoke DispatchMessage, ADDR msg

            invoke UpdateAndRender,hdc,hdcBack
        .ENDW
        mov eax,msg.wParam  ;return
        ret
WinMain endp

WinProc proc hWnd:HWND, uMsg:UINT, wParam:WPARAM, lParam:LPARAM      ; process events!
    .if (uMsg==WM_CREATE)
        xor eax, eax
        ret
    .elseif (uMsg==WM_KEYDOWN)
        xor eax, eax
        mov al, key_state
            .if (wParam==VK_UP)
                or  eax, 4       ;0100   set up
                and eax, 13      ;1101   kill down
            .elseif (wParam==VK_LEFT)
                or  eax, 8       ;1000   set left
                and eax, 14      ;1110   kill right
            .elseif (wParam==VK_RIGHT)
                or  eax, 1       ;0001   set right
                and eax, 7       ;0111   kill left
            .elseif (wParam==VK_DOWN)
                or  eax, 2       ;0010   set down
                and eax, 11      ;1011   kill up
            ;.else 
                ;nothing
            .endif
        mov key_state, al   ;return key_state
    .elseif (uMsg==WM_KEYUP)
        xor eax, eax
        mov al, key_state
            .if (wParam==VK_UP)
                and eax, 11      ;1011   kill up
            .elseif (wParam==VK_LEFT)
                and eax, 7       ;0111   kill left
            .elseif (wParam==VK_RIGHT)
                and eax, 14      ;1110   kill right
            .elseif (wParam==VK_DOWN)
                and eax, 13      ;1101   kill down
            ;.else 
                ;nothing
            .endif
        mov key_state, al
    .elseif (uMsg==WM_DESTROY)
        invoke PostQuitMessage,NULL
    .else
        invoke DefWindowProc,hWnd,uMsg,wParam,lParam
        ret
    .endif
    xor eax, eax
    ret
WinProc endp

UpdateAndRender proc hdc:HDC, hdcBack :HDC
        invoke GetDt
        invoke UpdateLogic
        invoke Render,hdc, hdcBack
    Ret
UpdateAndRender EndP

GetDt proc
    ;mov dtime, 32

    invoke GetTickCount
    mov ebx, prevTime
    mov prevTime, eax
    sub eax, ebx

    mov dtime, eax

    Ret
GetDt EndP

Render proc hdc:HDC, hdcBack:HDC

        invoke BitBlt,hdcBack, 0, 0, SCREEN_WIGTH, SCREEN_HEIGHT, 0, 0, 0,WHITENESS;BLACKNESS

    ;RENDER

        invoke RayCastingEngine,hdcBack
        ;invoke RenderWallK,hdcBack,1, 10, RenderColorTest

            ;Render coordinate
        invoke RenderCoord,hdcBack
        invoke TestRenderKeys, hdcBack

    ;END RENDER

        invoke BitBlt,hdc, 0, 0, SCREEN_WIGTH, SCREEN_HEIGHT, hdcBack, 0, 0,SRCCOPY
    ;invoke ReleaseDC,hWnd, hdc

    Ret
Render EndP

UpdateLogic proc
    ;MOVE LEFT, RIGHT
        ;Test if active key
                xor eax, eax
                or al, key_state
                and ax, 9  ;1001
                cmp eax, 0
                je  UpdateLogicNextKeys
        ;test left or right
            .if     (eax==1)        ;0001   ( key right)
                mov turnSign, 1
            .else                   ;1000   ( key left)
                mov turnSign, -1
            .endif

                fninit
                    fld     turnConst
                    fild    dtime
                    fmul
                    fild    turnSign
                    fmul
                    fld     player.Angle
                    fadd
                    fst     player.Angle

            ;make normal
                ;test <0
                    fldz
                    fld     player.Angle
                    fcomi   st(0), st(1)    ;cmp angle, 0
                wait
                jae norm_fprem
                    fld1
                    fldpi
                    fscale  ;2 pi
                    fld     player.Angle
                    fadd
                    fst     player.Angle
                jmp UpdateLogicNextKeys
                ;test >2pi
                norm_fprem:
                    fld1
                    fldpi
                    fscale                  ;2 pi
                    fld     player.Angle

                    fcomi   st(0), st(1)    ;cmp angle, 0
                wait
                    jb UpdateLogicNextKeys
                    fprem
                    fst     player.Angle
        UpdateLogicNextKeys:
    ;MOVE UP, DOWN
                        ;===========================need to write clipping!
        ;test if active key
            xor eax, eax
                or al, key_state
                and ax, 6  ;0110
                cmp eax, 0
            je  UpdateLogicExit

        .if (eax==4)                ;0100 (key up)
            mov turnSign, 1
        .else                       ;0010 (key down)
            mov turnSign, -1
        .endif

            fninit
                    fild    dtime
                    fld     moveConst
                    fmul
                    fild    turnSign
                    fmul
                    fst     bufd

                ; it's X
                    fld     player.Angle
                    fsin
                    fld     bufd
                    fmul
                    fld     player.X
                    fadd
                    fst     bufX_dd
                    fist    bufX_dw
                ;it's Y
                    fld     player.Angle
                    fcos
                    fld     bufd
                    fmul
                    fld     player.Y
                    fadd
                    fst     bufY_dd
                    fist    bufY_dw

            cmp bufY_dw,0
                jl UpdateLogicExit
            cmp  bufY_dw,64
                jg UpdateLogicExit
            cmp bufX_dw,0
                jl UpdateLogicExit
            cmp bufX_dw,64
                jg UpdateLogicExit

            ;xor eax, eax
            mov ax, bufY_dw
            CWDE
            mov bx, 65
            mul bx
            mov ebx, eax
            mov ax, bufX_dw
            CWDE
            add ebx, eax

            cmp ebx, 4225
            jge UpdateLogicExit

            mov esi, offset map
            mov al, [esi+ebx]

            cmp al, 1
            je  UpdateLogicExit

            fninit
                fld     bufX_dd
                fst     player.X

                fld     bufY_dd
                fst     player.Y
            wait

    UpdateLogicExit:
    Ret
UpdateLogic EndP

RenderWallK proc hdcBack:HDC, h:DWORD, x:DWORD, color:DWORD
    LOCAL l:DWORD
    LOCAL hPen:HPEN
    LOCAL holdPen:HPEN

    mov eax, h
    cmp eax, 0
    jl  uexit

    ; Calculate l and h
    mov eax, SCREEN_HEIGHT  ; SCREEN_HEIGHT + 1
    inc eax
    sub eax, h
    shr eax, 1
    mov l, eax
    add eax, h
    mov h, eax ; Now h is the bottom of the wall

    ; Draw ceiling
    invoke CreatePen, PS_SOLID, 1, CEILING_COLOR
    mov hPen, eax
    invoke SelectObject, hdcBack, hPen
    mov holdPen, eax

    invoke MoveToEx, hdcBack, x, 0, NULL
    invoke LineTo, hdcBack, x, l

    invoke SelectObject, hdcBack, holdPen
    invoke DeleteObject, hPen

    ; Draw wall
    invoke CreatePen, PS_SOLID, 1, color
    mov hPen, eax
    invoke SelectObject, hdcBack, hPen
    mov holdPen, eax

    invoke MoveToEx, hdcBack, x, l, NULL
    invoke LineTo, hdcBack, x, h

    invoke SelectObject, hdcBack, holdPen
    invoke DeleteObject, hPen

    ; Draw floor
    invoke CreatePen, PS_SOLID, 1, FLOOR_COLOR
    mov hPen, eax
    invoke SelectObject, hdcBack, hPen
    mov holdPen, eax

    invoke MoveToEx, hdcBack, x, h, NULL
    invoke LineTo, hdcBack, x, SCREEN_HEIGHT

    invoke SelectObject, hdcBack, holdPen
    invoke DeleteObject, hPen

uexit:
    Ret
RenderWallK EndP

TestRenderKeys proc hdcBack:HDC
                    xor eax, eax

                    mov al, key_state
                    mov ebx, eax
                    and al, 4
                    je  t_k_left
                    invoke TextOut,hdcBack,1250,600,ADDR textkey_up,4
        t_k_left:   mov eax, ebx
                    and al, 8
                    je t_k_right
                    invoke TextOut,hdcBack,1200,650,ADDR textkey_left,4
        t_k_right:  mov eax, ebx
                    and al, 1
                    je t_k_down
                    invoke TextOut,hdcBack,1300,650,ADDR textkey_right,5
        t_k_down:   and bl, 2
                    je t_k_exit
                    invoke TextOut,hdcBack,1250,700,ADDR textkey_down,4
        t_k_exit:   

    Ret
TestRenderKeys EndP

RenderCoord proc   hdcBack:HDC                 ;out only integer part!

    ;print X coord
        invoke TextOut,hdcBack, 1100, 5, addr coordXe, 2
        fninit
            ;fnstcw bufw
            ;or     [bufw], 3072      ;10-11 bits   3= -> 0
            ;fldcw  bufw

            fld player.X
            frndint

            fist bufw
        wait
            invoke RtlZeroMemory, addr bufb, 10  
        ;xor eax, eax
        mov ax, bufw
        CWDE
        invoke dwtoa, eax, addr bufb
        invoke TextOut,hdcBack, 1120, 5, addr bufb, 10
    ;print Y coord
        invoke TextOut,hdcBack, 1100, 25, addr coordYe, 2
        fninit
            ;fnstcw bufw
            ;or     [bufw], 3072      ;10-11 bits   3= -> 0
            ;fldcw  bufw

            fld player.Y
            frndint

            fist bufw
        wait
            invoke RtlZeroMemory, addr bufb, 10
        mov ax, bufw
        CWDE
        invoke dwtoa, eax, addr bufb
        invoke TextOut,hdcBack, 1120, 25, addr bufb, 10
    ;print angle
        invoke TextOut,hdcBack, 1100, 55, addr coordAngle, 7
        fninit
            fld     player.Angle;bufd
            fild    num180
            fmul
            fldpi
            fdiv
            fist bufw
        wait
            invoke RtlZeroMemory, addr bufb, 10
        mov ax, bufw
        CWDE
        invoke dwtoa, eax, addr bufb
        invoke TextOut,hdcBack, 1152, 55, addr bufb, 10

    Ret
RenderCoord EndP


RayCastingEngine proc hdcBack:HDC
    LOCAL   cpixelX:DWORD
    LOCAL   scrX:DWORD
    LOCAL   scrH:DWORD
    LOCAL   scrCol:DWORD

        mov cpixelX, -682

    RayCastingEngineCycle:
            ;update angle for wall
            fninit
                fild    cpixelX
                fld     RadianPerPixel
                fmul
                fld     player.Angle
                fadd
                fst     bufAngle
            wait

            mov eax, cpixelX
            add eax, 682
            mov scrX, eax

            mov     lenWallY, 0
            mov     lenWallX, 0

            invoke FindWallRayY
            invoke FindWallRayX
            mov eax, lenWallY
            mov ebx, lenWallX

            .if (eax > ebx)
                mov scrH, eax
            .else   
                mov scrH, ebx
            .endif

            ; Set the wall color to green
            .if (scrH >= 1250) 
                mov scrCol, 0FF00h    ; Set to pure green
            .else
                fninit
                    fld     colorConst
                    fld     scrH
                    fdiv    st(0), st(1)
                    fist    scrCol
                wait     
                shl     scrCol,8     ; Shift into green component
            .endif

            invoke RenderWallK,hdcBack, scrH, scrX, scrCol

            next_w:
            inc cpixelX
            cmp cpixelX, 682
        jl  RayCastingEngineCycle

    RayCastingEngineExit:
    Ret

RayCastingEngine EndP 

FindWallRayY proc

    ;dx and dy
            fninit
                fld     bufAngle
                fsin
                fst     dxLook

                fld     bufAngle
                fcos
                fst     dyLook
            wait

    ;test dy 0
        fninit
            fld     dyLook
            fabs
            fld     epsilon
            fcomi  st(0), st(1)
        wait
            jae FindWallRayYExit

    ;make normal dy
        fninit     
            fld     dyLook
            fabs
            fld     dxLook
            fdiv    st(0), st(1)
            fst     dxLook

            fld     dyLook
            fld     dyLook
            fabs
            fdiv
            frndint
            fst     dyLook
        wait
    ;make x0, y0      
        fninit
            fld     num0dot5
            fld     dyLook
            fmul
            fchs    ;-0.5 or +0.5

            fld     player.Y
            frndint

            fadd    ;==y0

            fst     bufY_dd

            fld     player.Y
            fsub    st(0), st(1)    ;=Y-Y0

            fld     dxLook
            fmul                    ;=(Y-Y0)*dx

            fld     dyLook
            fdivp   st(1), st(0)    ;or fdivp   st(1), st(0)

            fchs
            fld     player.X
            fadd            ;its x0

            fst     bufX_dd

            fld epsilon
            fld dyLook
            fmul
            fst lookEpsilon
        wait

    ;Cycle
        FindWallRayYRepeat:
            fninit
                fld     dxLook
                fld     bufX_dd
                fadd
                fst     bufX_dd
                frndint
                fist    bufX_dw

                fld     dyLook
                fld     bufY_dd
                fadd
                fst     bufY_dd
                fld     lookEpsilon
                fadd
                frndint
                fist    bufY_dw
            wait

            cmp bufY_dw,0
                jl FindWallRayYExit
            cmp  bufY_dw,65
                jg FindWallRayYExit
            cmp bufX_dw,0
                jl FindWallRayYExit
            cmp bufX_dw,65
                jg FindWallRayYExit

            ;xor eax, eax
            mov ax, bufY_dw
            CWDE
            mov bx, 65
            mul bx
            mov ebx, eax
            mov ax, bufX_dw
            CWDE
            add ebx, eax

            cmp ebx, 4225
            jge FindWallRayYExit

            mov esi, offset map
            mov al, [esi+ebx]

            cmp al, 1
            jne FindWallRayYRepeat

                ;length sqrt(x^2 + y^2)
                fninit
                    fld     player.Y
                    fld     bufY_dd
                    fsub
                    fabs
                    fst     bufY_dd
                    fld     bufY_dd
                    fmul
                    fst     bufd

                    fld     player.X
                    fld     bufX_dd
                    fsub
                    fst     bufX_dd
                    fld     bufX_dd
                    fmul

                    fld     bufd
                    fadd
                    fsqrt

                    fild    WallConst
                    fdivr
                    fist    lenWallY
                wait

    FindWallRayYExit:  
    Ret
FindWallRayY EndP

FindWallRayX        proc
    ;dx and dy
            fninit
                fld     bufAngle
                fsin
                fst     dxLook

                fld     bufAngle
                fcos
                fst     dyLook
            wait

    ;test dx 0
        fninit
            fld     dxLook
            fabs
            fld     epsilon
            fcomi  st(0), st(1)
        wait
            jae FindWallRayXExit

    ;make normal dx
        fninit     
            fld     dxLook
            fabs
            fld     dyLook
            fdiv    st(0), st(1)
            fst     dyLook

            fld     dxLook
            fld     dxLook
            fabs
            fdiv
            frndint
            fst     dxLook
        wait  

    ;make x0, y0      
        fninit
            fld     num0dot5
            fld     dxLook
            fmul
            fchs    ;-0.5 or +0.5

            fld     player.X
            frndint

            fadd    ;==x0

            fst     bufX_dd

            fld     player.X
            fsub    st(0), st(1)    ;=X-X0

            fld     dyLook
            fmul                    ;=(X-X0)*dy

            fld     dxLook
            fdivp   st(1), st(0)    ;or fdivp   st(1), st(0)

            fchs
            fld     player.Y
            fadd            ;its y0

            fst     bufY_dd

            fld     epsilon
            fld     dxLook
            fmul
            fst lookEpsilon
        wait

    ;Cycle
        FindWallRayXRepeat:
            fninit
                fld     dyLook
                fld     bufY_dd
                fadd
                fst     bufY_dd
                frndint
                fist    bufY_dw

                fld     dxLook
                fld     bufX_dd
                fadd
                fst     bufX_dd
                fld     lookEpsilon
                fadd
                frndint
                fist    bufX_dw
            wait

            cmp bufY_dw,0
                jl FindWallRayXExit
            cmp  bufY_dw,64
                jg FindWallRayXExit
            cmp bufX_dw,0
                jl FindWallRayXExit
            cmp bufX_dw,64
                jg FindWallRayXExit

            ;xor eax, eax
            mov ax, bufY_dw
            CWDE
            mov bx, 65
            mul bx
            mov ebx, eax
            mov ax, bufX_dw
            CWDE
            add ebx, eax

            cmp ebx, 4225
            jge FindWallRayXExit

            mov esi, offset map
            mov al, [esi+ebx]

            cmp al, 1
            jne FindWallRayXRepeat

                ;length sqrt(x^2 + y^2)
                fninit
                    fld     player.Y
                    fld     bufY_dd
                    fsub
                    fabs
                    fst     bufY_dd
                    fld     bufY_dd
                    fmul
                    fst     bufd

                    fld     player.X
                    fld     bufX_dd
                    fsub
                    fst     bufX_dd
                    fld     bufX_dd
                    fmul

                    fld     bufd
                    fadd
                    fsqrt

                    fild    WallConst
                    fdivr
                    fist    lenWallX
                wait

    FindWallRayXExit:
    Ret
FindWallRayX EndP


InitMap proc
    LOCAL t:DWORD

        mov edi, offset map
        mov eax, 1
            stosb

        mov edi, offset map
        mov eax, 1
        add edi, 64
            stosb

        mov edi, offset map
        mov eax, 1
        add edi, 2242
        stosb

        inc edi
        stosb

        inc edi
        stosb

        inc edi
        stosb

        inc edi
        stosb

        inc edi
        stosb

        inc edi
        stosb

        add edi, 183
        stosb

        inc edi
        stosb

        inc edi
        stosb

        inc edi
        stosb

        inc edi
        stosb

        inc edi
        stosb

        add edi, 54

    Ret
InitMap EndP

end start
