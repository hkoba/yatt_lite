YATT::Lite - Template runs on PSGI.
==================

YATT is Yet Another Template Toolkit.
[YATT::Lite] is latest version of YATT, written in Pure Perl.

Unlike other template engines, YATT::Lite comes with its own Web Framework
([WebMVC0]) which runs on [PSGI], FastCGI and CGI.
So, you can concentrate on writing your most important parts: Views and Models.

Like PHP, (SiteApp of) YATT::Lite routes incoming requests directly into
``*.yatt`` template files in webapp's document directory. 
(Of course you can easily hide .yatt extension.
Also, you can define url routing patterns and per-directory hooks.
You can use many abstraction techniques too.)
Each templates are compiled on-the-fly and cached as perl scripts
so you can add/modify your templates while running your webapp.

Unlike PHP and other template engines, YATT has quite HTML-like syntax. 
All YATT syntax items are *namespace-prefixed* equivalents
of HTML syntax items. i.e. ``<!yatt:...>`` for declarations,
``<yatt:...>`` for invocations, ``&yatt:...;`` for entity references
and ``<?perl...?>`` for (dirty ;-) processing instructions.

You can define ``entity functions`` in ``app.psgi`` and/or
per-directory ``.htyattrc.pl`` script.
Entity functions are used like ``&yatt:myfunc(..);``
anywhere in .yatt templates
to embed variables, process user parameters and access backend databases.

Unlike Ruby-on-Rails and other major Web Frameworks,
YATT::Lite itself is Model-Agnostic.
In other words, YATT::Lite do not depend on any specific ORM.
So you can use your favorite ORMs.
(Actually, WebMVC0 contains some support for ORM ([DBIx::Class]),
but you are not limited to them.)

YATT focuses empowering Web Designers
--------------------

In contrast to other Web Frameworks, YATT is designed primarily to give
more power (with safety) to **Template Writers (Web Designers)**
who are usually not trained as programmers,
so that programmers can delegate more tasks to them.
(This means programmers can concentrate on fundamental infrastructure tasks
rather than view-related, biz-issue-specific, ad-hoc tasks.
And eventually, you might find
you can keep your programming team slim, fit and dense than others;-)

To make YATT easily understandable by Web Designers,
YATT has declarative, compositional semantics.
YATT allows them to define **new tags** (called *yatt widgets*).
So, from their point of view, YATT is just a seemless extension to HTML.

To give safety to Web Designers, YATT provides ``yatt lint``, 
which is integrated to [Emacs] via ``yatt-mode.el``.
Everytime they save a YATT template, yatt lint verifies it.
Syntax errors, spelling misses of variables, entities and widget names...
all such errors will be detected instantly,
and emacs will be directed to the line of the error.

Also, YATT has many safer default behaviors, ie. automatic output escaping
based on argument type declaration and config file naming convention
which helps access protection.


INSTALLATION
--------------------

YATT::Lite is now on CPAN, so you can install YATT::Lite like
other CPAN modules.

    $ cpanm YATT::Lite

Also, if you want to use latest version of YATT::Lite,
and if you already have Plack and other modules,
you can install YATT::Lite just through git command.
(But see [NON-STANDARD DIRECTORY STRUCTURE](#non-standard-directory-structure))

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
Open your favorite editor and create a yatt template ``html/index.yatt``
like this:

```html
<!yatt:args x y>
<h2>Hello &yatt:x; world!</h2>
&yatt:y;
```


Then try to access:
  
     http://0:5000/
     http://0:5000/?x=foo
     http://0:5000/?x=foo&y=bar

### Emacs integration (yatt-mode.el and yatt-lint-any-mode.el)

Currently, there is no installer for yatt-mode.el yet.
It depends on ``mmm-mode.el`` and ``cperl-mode.el``,
so please install them manually if you don't have them.

After that, to use yatt-mode,
you may need to add something like following to your ``.emacs``
(assuming you cloned yatt_lite git repository as ~/perl5/lib/YATT):

```elisp
(load "~/perl5/lib/YATT/elisp/yatt-autoload.el")
```

This adds autoload definition of ``yatt-mode``.
It also adds ``yatt-lint-any-mode.el``, which can do save-time check
for other perl-related files (*.pm, *.pl...) too.


SUPPORT AND DOCUMENTATION
--------------------

You can look for Source Code Repository at:

    https://github.com/hkoba/yatt_lite

In source distribution, 
basic documents are placed under ``YATT/Lite/docs``. You can read them via:
http://ylpodview-hkoba.dotcloud.com/
(But for now, most pods are not yet finished and written only in Japanese.)

Also, you can run ylpodview (POD viewer) locally like:

    cd lib
    plackup YATT/samples/ylpodview/approot/app.psgi

and try to access http://0:5000/

NON-STANDARD DIRECTORY STRUCTURE
--------------------

Unfortunately, YATT::Lite distribution doesn't conform
normal CPAN style directory structure. This is experimental,
but intentional. Because: 

1. I want to use YATT::Lite as git submodule(or symlink), for each project.
   This is to keep maximum freedom of code-evolution.
   So, allowing git clone as ``lib/YATT`` is the MUST for me.

2. Since I usually want to modify each installation instance of YATT::Lite,
   I need to bundle all test suits and support scripts too.
   So, scripts for yatt is placed under ``lib/YATT/scripts``.


COPYRIGHT AND LICENCE
--------------------

Copyright (C) 2007..2013 "KOBAYASI, Hiroaki"

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

[YATT::Lite]: http://ylpodview-hkoba.dotcloud.com/mod/YATT::Lite
[PSGI]: http://plackperl.org/
[WebMVC0]: http://ylpodview-hkoba.dotcloud.com/mod/YATT::Lite::WebMVC0::SiteApp
[DBIx::Class]: http://ylpodview-hkoba.dotcloud.com/mod/DBIx::Class
[Emacs]: http://www.gnu.org/software/emacs/
[cpanminus]: http://search.cpan.org/perldoc?App::cpanminus#INSTALL
