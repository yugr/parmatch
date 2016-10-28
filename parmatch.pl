#!/usr/bin/perl

# This is a simple tool which scans all .v files in a folder
# for module definitions
#   module M #(P1, P2, ...) ...
# and module instantiations:
#   M #(.P1(V1), .P2(V2), ...) ...
# and warns if some parameters have not been assigned (in a hope
# that this is a bug).
#
# Tool works at lexing level (i.e. AST is not built) so
# it may both miss some bugs ("false negative" in CS jargon,
# "type 1 errors" in math jargon) when parameters are declared
# outline (either directly or by including parameter list file) and
# report invalid warnings ("false positives", "type 2 errors") when
# parameters are assigned using defparam. It also totally ignores
# preprocessor directives.
#
# It's possible to fix above limitations but hopefully it's not necessary
# as outline parameters and defparams are bad and rare coding practices.

use strict;
use warnings;

use File::Find;
use Getopt::Long qw(GetOptions);
use Data::Dumper;

my $debug = 0;

{
  package Lexer;

  my @lines;
  my $cur_file;
  my $cur_line;

  sub init($) {
    $cur_file = $_[0];
    open FILE, $cur_file or die "unable to open $cur_file";
    @lines = <FILE>;
    close FILE;
    $cur_line = 1;
  }

  sub done() {
    return $#lines < 0;
  }

  sub warn($$) {
    # TODO: avoid dups?
    print STDERR "warning: $_[0]->{file}:$_[0]->{line}: $_[1]\n";
  }

  sub tok();  # To make compiler happy...
  sub tok() {
    # This code is intentionally simple.

    my $line;

    while(!$line) {
      return undef if(Lexer::done());

      $line = shift @lines;

      # Skip whites
      while(1) {
        next if($line =~ s/^[\s\r\n]+//m);
        next if($line =~ s/^\/\/.*//);
        next if($line =~ s/^\\$//);
        if($line =~ /^\/\*/) {
          while($line !~ s/^(.*?)\*\/// && !done()) {
            $line = shift @lines;
            ++$cur_line;
          }
          next;
        }
        last;
      }

      if($line) {
        last;
      } else {
        ++$cur_line;
      }
    }

    my $type;
    my $info = undef;
    my $nline = $cur_line;

    # Useful ref: http://www.verilog.com/VerilogBNF.html
    if($line =~ s/^([a-zA-Z_\$.][a-zA-Z_\$.\d]*)//) {
      $info = $1;
      $type = $info =~ /^(begin|end|(end)?(module|case|generate)|parameter|localparam|type|real|integer|logic|wire|reg|(real)?time|assign|(pos|neg)edge)$/ ? 'keyword'
              : $info =~ /^\./ ? 'param_bind'
              : 'id';
      $info =~ s/^\.//;
    } elsif($line =~ s/^\\(\S+)\s//) {  # Escaped id
      $info = $1;
      $type = 'id';
    } elsif($line =~ s/^([0-9'][0-9'bBoOdDhHxXzZsS_.]*)//) {
      $info = $1;
      $type = 'number';
    } elsif($line =~ s/^#([0-9][0-9.]*)//) {
      $info = $1;
      $type = 'delay';
    } elsif($line =~ s/^(<=|>=|&&|\|\||[;,#(){}=?:!<>~|&^+\-*%@\/\[\]])//) {
      $type = $1;
    } elsif($line =~ s/"((?:\\"|[^"])*)"//) {
      $info = $1;
      $info =~ s/\\"/"/g;
      $type = 'string';
    } elsif($line =~ s/`([a-zA-Z_0-9]+)//) {
      $info = $1;
      $type = 'macro';
    } else {
      Lexer::warn({ line => $cur_line, file => $cur_file }, "failed to recognize token '$line'");
      $line = '';
    }
    print STDERR "$cur_file:$cur_line: token '$type'" . (defined $info ? " ($info)\n" : "\n") if($debug > 1);

    if($line) {
      unshift @lines, $line;
    } else {
      ++$cur_line;
    }

    return {
      type => $type,
      info => $info,
      file => $cur_file,
      line => $nline
    };
  }

  # Reads )-terminated, comma-separated list
  sub read_list() {
    my @elems;
    my $e = [];
    my $nest = 1;
    while(!Lexer::done()) {
      my $l = Lexer::tok();
      next if(!defined $l);
      my $ty = $l->{type};
      if($ty eq '(') {
        ++$nest;
      } elsif($ty eq ')') {
        if(!--$nest) {
          push @elems, $e;
          last;
        }
      } elsif($ty eq ',' && $nest == 1) {
        push @elems, $e;
        $e = [];
      } else {
        push @$e, $l;
      }
    }
    return @elems;
  }
}

my %mod2info;

sub is_verilog_file($) {
  $_[0] =~ /\.(v|sv|vh|svh|ver)$/i;
}

sub is_module_tok($) {
  my $l = $_[0];
  return defined $l
    && defined $l->{type}
    && $l->{type} eq 'keyword'
    && $l->{info} eq 'module';
}

sub maybe_read_param_lparen() {
  my $tok = Lexer::tok();
  return 0 if(!defined $tok || !defined $tok->{type} || $tok->{type} ne '#');

  $tok = Lexer::tok();
  return 0 if(!defined $tok || !defined $tok->{type} || $tok->{type} ne '(');

  return 1;
}

my @excludes;

sub is_excluded($) {
  my $file = $_[0];
  foreach(@excludes) {
    return 1 if($file =~ /$_/);
  }
  return 0;
}

my @verilog_files;

sub find_verilog_files() {
  if(is_verilog_file($File::Find::name)
     && !is_excluded($File::Find::name)) {
    push @verilog_files, $File::Find::name;
  }
}

sub find_defs($) {
  my $file = $_[0];
  print "Scanning $file for module definitions...\n";

  Lexer::init($file);
  while(!Lexer::done()) {
    my $l = Lexer::tok();
    next if(!is_module_tok($l));

    my $mod = Lexer::tok();
    my $mod_name = $mod->{info};
    my $mod_loc = "$mod->{file}:$mod->{line}";

    next if(!maybe_read_param_lparen());

    my @par_list = Lexer::read_list();
    print STDERR "$mod_loc: find_defs module params:\n" . Dumper(@par_list) if($debug);

    # Analyze pars
    my @pars;
    my %pars_hash;
    foreach my $ll (@par_list) {
      my $par;
      for my $l (@$ll) {
        if ($l->{type} eq 'keyword') {
          next;
        } elsif($l->{type} eq 'id') {
          $par = $l->{info};
          last;
        }
      }
      push @pars, $par;
      if(!defined $par) {
        Lexer::warn($mod, "failed to parse $#pars-th parameter of module '$mod_name'");
      } else {
        $pars_hash{$par} = 1;
        print STDERR "$mod_loc: $#pars-th parameter: " . Dumper($par) if($debug);
      }
    }

    if(!exists $mod2info{$mod_name}) {
      $mod2info{$mod_name} = {
        tok => $mod,
        pars => \@pars,
        hash => \%pars_hash,
        warned => 0,
        ignore_pos => 0
      };
      next;
    }

    # It's common for single codebase to have
    # several implementations of same module.
    # It's fine if their signature match.
    # If they don't, we warn user and ignore
    # such module.

    my $prev = $mod2info{$mod_name};
    my $prev_mod_loc = "$prev->{tok}->{file}:$prev->{tok}->{line}";
    my $prev_pars = $prev->{pars};
    my $prev_npars = @$prev_pars;
    my $prev_hash = $prev->{hash};

    my $npars = @pars;

    # First check pars that were not seen in previous def
    my @new_pars;
    for(my $i = 0; $i < $npars; ++$i) {
      my $par = $pars[$i];
      if(!exists $prev_hash->{$par}) {
        push @new_pars, $par;
        $prev->{ignore_pos} = 1;
      }
    }

    # Check missing pars
    my @miss_pars;
    for(my $i = 0; $i < $prev_npars; ++$i) {
      my $par = $prev_pars->[$i];
      if(defined $par && !exists $pars_hash{$par}) {
        push @miss_pars, $par;
        $prev->{ignore_pos} = 1;
        $prev_pars->[$i] = undef;
        delete $prev_hash->{$par};
      }
    }

    # Finally check for reordered pars (as these would prevent
    # analysis of positional params)
    my @reorder_pars;
    for(my $i = 0; $i < $npars; ++$i) {
      my $par = $pars[$i];
      if(exists $prev_hash->{$par}) {
        my $prev_par = $prev_pars->[$i];
        if(defined $prev_par && $par ne $prev_par) {
          push @reorder_pars, $par;
          $prev->{ignore_pos} = 1;
        }
      }
    }

    # TODO: disable further analysis of module if changes are too large?
    if(!$prev->{warned} && (@new_pars || @miss_pars)) {
      print STDERR "warning: $mod_loc: incompatible redefinition of module '$mod_name' (previously defined at $prev_mod_loc); following parameters will not be analyzed:\n";
      print STDERR "  newly added parameters: @new_pars \n" if(@new_pars);
      print STDERR "  missing parameters: @miss_pars \n" if(@miss_pars);
      $prev->{warned} = 1;
    }
  }
}

sub can_expect_mod_inst($) {
  return ($_[0]->{type} eq 'keyword' && $_[0]->{info} =~ /begin|end|generate/)
    || $_[0]->{type} eq ';';
}

my $verbose = 0;
my $aggress = 0;

sub check_insts($) {
  my $file = $_[0];
  print "Scanning $file for module instantiations...\n";

  Lexer::init($file);
  my $check_mod_inst = 1;
  while(!Lexer::done()) {
    my $l = Lexer::tok();
    next if(!defined $l || !defined $l->{type});

    # Do not check for insts in bad contexts
    if(!$aggress && !$check_mod_inst) {
      $check_mod_inst = can_expect_mod_inst($l);
      next;
    }

    $check_mod_inst = can_expect_mod_inst($l);

    my $name = $l->{info};
    my $loc = "$l->{file}:$l->{line}";

    # Skip unknown modules
    next if($l->{type} ne 'id' || !exists $mod2info{$name});

    my @pars;

    if(maybe_read_param_lparen()) {
      my @par_list = Lexer::read_list();
      print STDERR "$loc: '$name' instantiation parsed params:\n" . Dumper(@par_list) if($debug);

      # Analyze pars
      foreach my $ll (@par_list) {
        my $l = $ll->[0];
        my $par = $l->{type} eq 'param_bind' ? $l->{info} : undef;
        push @pars, $par;
        print STDERR "$loc: $#pars-th analyzed param is " . (defined $par ? "$par\n" : "undef\n") if($debug);
      }
    }

    my $mod_info = $mod2info{$name};
    next if($mod_info->{ignore});

    my $mod_pars = $mod_info->{pars};
    my $mod_loc = "$mod_info->{tok}->{file}:$mod_info->{tok}->{line}";

    if(!$mod_info->{warned} && scalar @pars > scalar @$mod_pars) {
      Lexer::warn($l, sprintf("no. of instantiation parameters (%d) > no. of defined parameters (%d) in module '$name' (defined at $mod_loc)", scalar @pars, scalar @$mod_pars)) if(!$verbose);
      next;
    }

    my %binds;
    my $pos_params = 0;
    for(my $i = 0; $i < @pars; ++$i) {
      my $par = $pars[$i];
      if(!defined $par) {
        # Positional param
        $binds{$mod_pars->[$i]} = 1;
        $pos_params = 1;
      } else {
        # Named param
        $binds{$par} = 1;
        if(!exists $mod_info->{hash}->{$par}) {
          # See above warning.
          Lexer::warn($l, "named parameter '$par' missing in module '$name' (defined at $mod_loc)") if(!$verbose);
        }
      }
    }

    next if($pos_params && $mod_info->{ignore_pos});

    # TODO: cumulated report for all params
    foreach my $par (@$mod_pars) {
      if(defined $par && !exists $binds{$par}) {
        print "$loc: parameter '$par' not assigned in instantiation of module '$name' (defined at $mod_loc)\n";
      }
    }
  }
}

my $help = 0;
my @exclude_files;

GetOptions(
  'help'            => \$help,
  'verbose+'        => \$verbose,
  'exclude=s@'      => \@excludes,
  'exclude-from=s@' => \@exclude_files,
  'debug+'          => \$debug,
  'aggress'         => $aggress
);

if($help) {
  print <<EOF;
Usage: parmatch.pl [OPT]... ROOT...

A sloppy script for finding unbound parameters in
Verilog module instantiations.

ROOT is either a folder or file with names of Verilog files to
analyze.

OPT can be one of
  --help                     Print this help and exit.
  --verbose                  Show more warning.
  --exclude=GLOB             Exclude files whose names match wildcard.
  --exclude-from=GLOB_FILE   Exclude files whose names match patterns
                             in file.

Internal options (only for testing!):
  --debug
  --aggress
EOF
  exit(0);
}

if($#ARGV < 0) {
  print STDERR "No root folders present at command line\n";
  exit(1);
}

my @roots = @ARGV;

foreach my $f (@exclude_files) {
  open FILE, $f or die "unable to open exclude file $f";
  while(<FILE>) {
    push @excludes, $_;
  }
  close FILE;
}

# Poor man's wildcards...
@excludes = map { s/\*/.*/g; s/\./\\./; s/\?/./; $_ } @excludes;

foreach my $root (@roots) {
  if(-d $root) {
    find({ wanted => \&find_verilog_files, no_chdir => 1}, $root);
  } else {
    open ROOT, $root or die "unable to open file $root";
    while(<ROOT>) {
      chop;
      if(!-f $_) {
        print STDERR "File not found: '$_'\n";
      } elsif(!is_verilog_file($_)) {
        print STDERR "File '$root' does not look like a Verilog file";
      } else {
        push @verilog_files, $_;
      }
    }
    close ROOT;
  }
}

foreach my $file (@verilog_files) {
  find_defs($file);
}

foreach my $file (@verilog_files) {
  check_insts($file);
}

# TODO: print summary?

