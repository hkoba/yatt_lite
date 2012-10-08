YATT::Lite version 0.0.4
==================

YATT is Yet Another Template Toolkit, aimed at Web Designers, rather than
well-trained programmers. To achieve this goal, YATT provides more
readable syntax for HTML/XML savvy designers, ``lint'' for static syntax
checking and many safer default behaviors, ie. automatic output escaping
based on argument type declaration and config file naming convention
which helps access protection.

YATT::Lite is template-syntax-compatible, lightweight, full rewrite of
YATT with superior functionalities.

In YATT, basic building block is called ``widget''. Template text is
treated as a sequence of ``widget definition'', each of which is leaded by
``widget declaration: <!yatt:widget>'', like multipart email.

A widget is translated into a perl subroutine (on memory, currently).  A
template text is translated into a perl package (class). The translation
is per-template basis and occurs on demand of widget. Template can be
given to YATT::Lite as a data(string/hash), filename or directory name.

Package name of template is automatically generated with respect to
option and filepath. If template is loaded from filesystem, it is cached
and reloaded if modified.

Although widget is basically 'named', head of each template text can be a
``unnamed (default) widget'', so that designers can treat a template file
itself as a widget. This means plain HTML files *just works* as template set.

In future, mainline YATT will incorporate YATT::Lite interface. It
means, today, if you want to adapt next generation YATT before its
release, write your script using YATT::Lite.

This is (still) alpha release. Although template syntax and facade(YATT::Lite)
API became stable (I want), internal modules are *open* for discussion.


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

Then you can use sample app.psgi to start yatt-enabled webapp, like this:

    cp lib/YATT/samples/app.psgi .
    mkdir html
    plackup

Now you are ready to write your first index.yatt.
Open your favorite editor and create html/index.yatt like this:

```html
<!yatt:args x y>
<h2>Hello &yatt:x; world!</h2>
&yatt:y;
```


Then try to access:
  
     http://0:5000/
     http://0:5000/?x=foo
     http://0:5000/?x=foo&y=bar


NON-STANDARD DIRECTORY STRUCTURE
--------------------

Unfortunately, YATT::Lite distribution doesn't conform
normal CPAN style structure. This is experimental,
but intentional. Because:

1. Engine(modules) and support scripts should be directory bundled together.
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

Copyright (C) 2007..2012 "KOBAYASI, Hiroaki"

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
