# -*- mode: perl; coding: utf-8 -*-

conflicts 'YATT';

requires 'perl' => '>= 5.10.1, != 5.17, != 5.19.3';
# >= 5.10.1, for named capture and //
# != 5.17, to avoid death by 'given is experimental'
# != 5.19.3 ~ 5.19.11, to avoid sub () {$value} changes

requires 'List::Util' => 0;
requires 'List::MoreUtils' => 0;
requires 'Plack' => 0;
requires 'version' => 0.77;
requires 'parent' => 0;

requires 'URI::Escape' => 0;
requires 'Tie::IxHash' => 0; # For nested_query
requires 'Devel::StackTrace' => 0;

# For perl 5.20. Actually, CGI is not required (I hope).
requires CGI => 0;
requires 'HTML::Entities' => 0;

recommends 'YAML::Tiny' => 0;
recommends 'Devel::StackTrace::WithLexicals' => 0.08;

configure_requires 'Module::CPANfile';
configure_requires 'Module::Build';

on test => sub {
 requires 'Test::More' => 0;
 requires 'Test::Differences' => 0;
 requires 'Test::WWW::Mechanize::PSGI' => 0;
 requires 'HTML::Entities' => 0;

 recommends 'DBD::SQLite' => 0;
 recommends 'DBD::mysql' => 0;
 recommends 'DBIx::Class' => 0;
 recommends 'CGI::Session' => 0;
 recommends 'Pod::Simple::SimpleTree' => 0;
 recommends 'HTTP::Headers' => 0;
 recommends 'FCGI::Client' => 0;
 recommends 'Locale::PO' => 0;
 recommends 'Email::Simple' => 0;
 recommends 'Email::Sender' => 0;
};
