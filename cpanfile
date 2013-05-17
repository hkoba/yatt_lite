# -*- mode: perl; coding: utf-8 -*-

conflicts 'YATT';

requires 'perl' => '5.10.1'; # for named capture and //
requires 'List::Util' => 0;
requires 'List::MoreUtils' => 0;
requires 'Plack' => 0;
recommends 'YAML::Tiny' => 0;

configure_requires 'Module::CPANfile';
configure_requires 'Module::Build';

on test => sub {
 requires 'Test::More' => 0;
 requires 'Test::Differences' => 0;
 requires 'Test::WWW::Mechanize::PSGI' => 0;

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
