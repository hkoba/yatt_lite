%define yatt       yatt_lite
%define modname    YATT-Lite
%define cgi_bin    %{_var}/www/cgi-bin
%define http_cfdir %{_sysconfdir}/httpd/conf.d

Summary: Yet Another Template Toolkit for perl
Name: perl-YATT-Lite
Version: 0.0.2
Release: 1%{?dist}
License: GPL+ or Artistic
Group: Development/Languages
URL: http://github.com/hkoba/%{yatt}
Source0: %{modname}-%{version}.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
buildarch: noarch
Requires: perl >= 5.10, mod_fcgid, zsh
# Requires: perl(Test::More), perl(Test::Differences), perl(Devel::Cover)
# Requires: perl(Sys::Syscall)

%description
YATT::Lite is Yet Another Template Toolkit, aimed at Web Designers,
rather than well-trained programmers. To achieve these goal, YATT
provides more readable syntax for HTML/XML savvy designers, ``yatt.lint''
for static syntax checking and many safer default behaviors,
ie. automatic output escaping based on argument type declaration and
file extension based visibility handling of template.

%prep
%setup -q -n %{modname}-%{version}

%build
true

%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT%{cgi_bin}
mkdir -p $RPM_BUILD_ROOT%{http_cfdir}
mkdir -p $RPM_BUILD_ROOT%{_bindir}
mkdir -p $RPM_BUILD_ROOT%{_datadir}/perl5
mkdir -p $RPM_BUILD_ROOT%{_datadir}/emacs/site-lisp

for e in cgi lib ytmpl; do
  cp -va runyatt.$e $RPM_BUILD_ROOT%{cgi_bin}/%{yatt}.$e
done

ln -vnsf %{yatt}.cgi \
   $RPM_BUILD_ROOT%{cgi_bin}/%{yatt}.fcgi

# XXX: This assumes %{_datadir} is /usr/share.
ln -vnsf ../../..%{cgi_bin}/%{yatt}.lib/YATT \
   $RPM_BUILD_ROOT%{_datadir}/perl5

ln -vnsf ../../../..%{cgi_bin}/%{yatt}.lib/YATT/elisp \
   $RPM_BUILD_ROOT%{_datadir}/emacs/site-lisp/yatt

# XXX: Directly expose yatt.* may be bad idea.
pushd $RPM_BUILD_ROOT%{_bindir}
for f in ../../%{cgi_bin}/%{yatt}.lib/YATT/scripts/yatt.*; do
    ln -vnsf $f .
done
popd

cp -va vendor/redhat/%{yatt}.conf $RPM_BUILD_ROOT/%{http_cfdir}/%{yatt}.conf
echo Action x-yatt-handler /cgi-bin/%{yatt}.cgi >> \
     $RPM_BUILD_ROOT/%{http_cfdir}/%{yatt}.conf

%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%doc
%{_bindir}/yatt.*
%{cgi_bin}/%{yatt}.cgi
%{cgi_bin}/%{yatt}.fcgi
%{cgi_bin}/%{yatt}.lib
%{cgi_bin}/%{yatt}.ytmpl
%config %{http_cfdir}/%{yatt}.conf
%{_datadir}/perl5/YATT
%{_datadir}/emacs/site-lisp/yatt
%{_datadir}/emacs/site-lisp/yatt/*.el

%changelog
* Tue Sep 28 2010 KOBAYASI Hiroaki <hkoba@sourceforege.net> - 0.0.1-1
- Initial build.

