Programs for ReactOS in AOK VM

"Get Programs" on the desktop (GET.CMD in C:\AOK\Programs) downloads the
programs below from their makers' own sites, about 180 MB, checks each
against the SHA-1 in FILES.TXT (which also says where each comes from), and
installs them all. It needs the network once, and takes a while; if the
network drops, run it again: what it already has is kept. C:\AOK-get.log
says what it fetched.

On a CD made with AOK VM's make-cd.sh, double-click INSTALL.CMD instead: the
same programs, with no network.

Either way they are installed with no questions. Afterwards they are in the
Start menu, under Programs, and C:\AOK-install.log says how each install
went.

  7-Zip                    archives
  Notepad++ 6.9            a text editor
  SumatraPDF 3.1.2         PDF reader
  AbiWord 2.9.4            word processor
  Media Player Classic HC  video and audio
  PuTTY 0.83               ssh and telnet
  WinSCP 5.7.7             file transfer
  Mypal 29.3               web browser
  Tux Paint 0.9.22         drawing
  LZDoom with Freedoom     the game
  OpenTTD 1.10.3           transport tycoon, with the OpenGFX graphics
  DOSBox 0.74-3            DOS programs and games
  Python 3.4.4             in C:\Python34
  Explorer++ 1.3.5         a file manager
  The Powder Toy           a falling-sand game
  Tiny C Compiler 0.9.27   in C:\tcc; "Tiny C Compiler prompt" puts it on the PATH
  Mesa 3D 17.0.1           OpenGL 3.0 (llvmpipe, on the CPU), and with it
                           Direct3D, which ReactOS draws through OpenGL

Mesa takes over OpenGL. Old programs that need only OpenGL 1.1 can run
faster on ReactOS's own: Control Panel, OpenGL Configuration, Renderer
"ReactOS Software Implementation" (or Mesa3D to go back). To install Mesa by
itself, double-click SETUP\mesa3d_setup.exe.

All are open source, each from its own makers, as ReactOS's Applications
Manager lists them (it installs the same ones over the network, one by one).
