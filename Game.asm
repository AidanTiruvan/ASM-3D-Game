;-------------------------------------------------------------------------------------------------------------------
; Epic 3D Game  in x86 ASM - (c) 2024 Aidan Tiruvan
;-------------------------------------------------------------------------------------------------------------------
 
; Compiler directives
 
.386                        ; Full 80386 instruction set
.model flat, stdcall                
option casemap:none             ; System Identifiers
 
 
; Stuff for MASM
include \masm32\include\windows.inc     
include \masm32\include\user32.inc      
include \masm32\include\kernel32.inc        
include \masm32\include\gdi32.inc       
 
; Libraries
 
includelib \masm32\lib\kernel32.lib     
includelib \masm32\lib\user32.lib       
includelib \masm32\lib\gdi32.lib        
 
; Window Settings
 
WinMain proto :DWORD, :DWORD, :DWORD, :DWORD    
 
; Constants and Datra
 
WindowWidth equ 640             ; How big the Window should be 
WindowHeight    equ 480
 
.DATA
 
ClassName       db "MyWinClass", 0      
AppName     db "Game Project in Assembly", 0     ; The name of the main Window
 
.DATA?                      
 
hInstance   HINSTANCE ?         
CommandLine LPSTR     ?                     
 
;-------------------------------------------------------------------------------------------------------------------
.CODE                       ; Where game should be

;-------------------------------------------------------------------------------------------------------------------
 
MainEntry proc
 
    LOCAL   sui:STARTUPINFOA        
 
    push    NULL                
    call    GetModuleHandle         
    mov hInstance, eax          
 
    call    GetCommandLineA         
    mov CommandLine, eax
 


 
    lea eax, sui            
    push    eax
    call    GetStartupInfoA         
    test    sui.dwFlags, STARTF_USESHOWWINDOW   
    jz  @1
    push    sui.wShowWindow         
    jmp @2
@1:
    push    SW_SHOWDEFAULT          
@2: 
    push    CommandLine
    push    NULL
    push    hInstance
    call    WinMain
 
    push    eax
    call    ExitProcess
 
MainEntry endp
 
; 
; WinMain - main entry point
;
 
WinMain proc hInst:HINSTANCE, hPrevInst:HINSTANCE, CmdLine:LPSTR, CmdShow:DWORD
 
    LOCAL   wc:WNDCLASSEX           
    LOCAL   msg:MSG
    LOCAL   hwnd:HWND
 
    mov wc.cbSize, SIZEOF WNDCLASSEX        
    mov wc.style, CS_HREDRAW or CS_VREDRAW  
    mov wc.lpfnWndProc, OFFSET WndProc      
    mov wc.cbClsExtra, 0            
    mov wc.cbWndExtra, 0            
    mov eax, hInstance
    mov wc.hInstance, eax           
    mov wc.hbrBackground, COLOR_3DSHADOW+1  
    mov wc.lpszMenuName, NULL           
    mov wc.lpszClassName, OFFSET ClassName  
 
    push    IDI_APPLICATION             ; Default application icon
    push    NULL    
    call    LoadIcon
    mov wc.hIcon, eax
    mov wc.hIconSm, eax
 
    push    IDC_ARROW               ; Default cursor
    push    NULL
    call    LoadCursor
    mov wc.hCursor, eax
 
    lea eax, wc
    push    eax
    call    RegisterClassEx             
 
    push    NULL                    
    push    hInstance               
    push    NULL                    
    push    NULL                    
    push    WindowHeight                
    push    WindowWidth             
    push    CW_USEDEFAULT               
    push    CW_USEDEFAULT               
    push    WS_OVERLAPPEDWINDOW + WS_VISIBLE    
    push    OFFSET AppName              ; The window title 
    push    OFFSET ClassName            
    push    0                   
    call    CreateWindowExA
    cmp eax, NULL
    je  WinMainRet              
    mov hwnd, eax               
 
    push    eax                 
    call    UpdateWindow
 
MessageLoop:
 
    push    0
    push    0
    push    NULL
    lea eax, msg
    push    eax
    call    GetMessage              
 
    cmp eax, 0                  
    je  DoneMessages
 
    lea eax, msg                
    push    eax
    call    TranslateMessage
 
    lea eax, msg                
    push    eax
    call    DispatchMessage
 
    jmp MessageLoop
 
DoneMessages:
    
    mov eax, msg.wParam             
 
WinMainRet:
    
    ret
 
WinMain endp
 
;
; WndProc - Main Window Procedure
;
 
WndProc proc hWnd:HWND, uMsg:UINT, wParam:WPARAM, lParam:LPARAM
 
    LOCAL   ps:PAINTSTRUCT              
    LOCAL   rect:RECT
    LOCAL   hdc:HDC
 
    cmp uMsg, WM_DESTROY
    jne NotWMDestroy
 
    push    0                   
    call    PostQuitMessage             ; Quit application
    xor eax, eax                
    ret
 
NotWMDestroy:
 
    cmp uMsg, WM_PAINT
    jne NotWMPaint
 
    lea eax, ps                 
    push    eax
    push    hWnd
    call    BeginPaint              
    mov hdc, eax
 
    push    TRANSPARENT
    push    hdc
    call    SetBkMode               ; Make text have a transparent background
 
    lea eax, rect               
    push    eax                 
    push    hWnd
    call    GetClientRect
 
    push    DT_SINGLELINE + DT_CENTER + DT_VCENTER
    lea eax, rect
    push    eax
    push    -1
    push    OFFSET AppName
    push    hdc
    call    DrawText                
 
    lea eax, ps
    push    eax
    push    hWnd
    call    EndPaint                
 
    xor eax, eax                
    ret
 
NotWMPaint:
    
    push    lParam
    push    wParam
    push    uMsg
    push    hWnd
    call    DefWindowProc               
    ret                     
 
WndProc endp
 
END MainEntry                       