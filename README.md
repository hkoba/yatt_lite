YATT::Lite version 0.0_5
==================

YATT is Yet Another Template Toolkit, aimed at Web Designers, rather than
well-trained programmers. To achieve this goal, YATT provides more
readable syntax for HTML/XML savvy designers, ``lint`` for static syntax
checking and many safer default behaviors, ie. automatic output escaping
based on argument type declaration and config file naming convention
which helps access protection.

YATT::Lite is template-syntax-compatible, lightweight, full rewrite of
YATT with superior functionalities.

INSTALLATION
--------------------

It's all pure Perl, so it's ok to put the .pm files (or git repo itself)
in their appropriate perl @INC path.
(But see NON-STANDARD DIRECTORY STRUCTURE)

The easiest way to use this distribution in your project is:

    git clone git://github.com/hkoba/yatt_lite.git lib/YATT

    # or If your project is managed in git, clone as submodule like this:

    git submodule add git://github.com/hkoba/yatt_lite.git lib/YATT
    git submodule init
    git submodule update

To create a yatt-enabled webapp, just copy sample app.psgi and run plackup:

    cp lib/YATT/samples/app.psgi .
    mkdir html
    plackup

Now you are ready to write your first yatt app.
Open your favorite editor and create F<html/index.yatt> like this:

```html
<!yatt:args x y>
<h2>Hello &yatt:x; world!</h2>
&yatt:y;
```


Then try to access:
  
     http://0:5000/
     http://0:5000/?x=foo
     http://0:5000/?x=foo&y=bar


DOCUMENTS
----------

Basic documents are placed under YATT/Lite/docs. You can read them via:
http://ylpodview-hkoba.dotcloud.com/
(But for now, most pods are not yet finished and written only in Japanese.)

Also, you can run ylpodview (document viewer) locally like:

    cd lib
    plackup YATT/samples/ylpodview/approot/app.psgi

and try to access http://0:5000/

NON-STANDARD DIRECTORY STRUCTURE
--------------------

Unfortunately, YATT::Lite distribution doesn't conform
normal CPAN style structure. This is experimental,
but intentional. Because:

1. Engine(modules) and support scripts should be directly bundled together.
   To achieve this, scripts/* and elisp/* is placed in YATT/.

2. Since YATT::Lite is still evolving, single (system-wide) installation
   may not fit for multi-service site. To isolate instability risk,
   individual service should have its own installation of engine.
   To achieve this, runyatt.cgi uses runyatt.lib first.

SUPPORT AND DOCUMENTATION
--------------------

You can also look for Source Code Repository at:

        https://github.com/hkoba/yatt_lite
        git://github.com/hkoba/yatt_lite.git


COPYRIGHT AND LICENCE
--------------------

Copyright (C) 2007..2013 "KOBAYASI, Hiroaki"

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
