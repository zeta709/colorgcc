#! /usr/bin/perl -w

#
# colorgcc
#
# Version: 1.3.2
#
# $Id: colorgcc,v 1.10 1999/04/29 17:15:52 jamoyers Exp $
#
# A wrapper to colorize the output from compilers whose messages
# match the "gcc" format.
#
# Requires the ANSIColor module from CPAN.
#
# Usage:
#
# In a directory that occurs in your PATH _before_ the directory
# where the compiler lives, create a softlink to colorgcc for
# each compiler you want to colorize:
#
#    g++ -> colorgcc
#    gcc -> colorgcc
#    cc  -> colorgcc
#    etc.
#
# That's it. When "g++" is invoked, colorgcc is run instead.
# colorgcc looks at the program name to figure out which compiler to run.
#
# The default settings can be overridden with ~/.colorgccrc.
# See the comments in the sample .colorgccrc for more information.
#
# Note:
#
# colorgcc will only emit color codes if:
# 
#    (1) Its STDOUT is a tty and
#    (2) the value of $TERM is not listed in the "nocolor" option.
#
# If colorgcc colorizes the output, the compiler's STDERR will be
# combined with STDOUT. Otherwise, colorgcc just passes the output from
# the compiler through without modification.
# 
# Author: Jamie Moyers <jmoyers@geeks.com>
# Started: April 20, 1999
# Licence: GNU Public License
#
# Credits:
#
#    I got the idea for this from a script called "color_cvs":
#       color_cvs .03   Adrian Likins <adrian@gimp.org> <adrian@redhat.com>
#
#    <seh4@ix.netcom.com> (Scott Harrington)
#       Much improved handling of compiler command line arguments.
#       exec compiler when not colorizing to preserve STDOUT, STDERR.
#       Fixed my STDIN kludge.
#       
#    <ecarotti@athena.polito.it> (Elias S. G. Carotti)
#       Corrected handling of text like -DPACKAGE=\"Package\"
#       Spotted return code bug.
#
#    <erwin@erwin.andreasen.org> (Erwin S. Andreasen)
#    <schurchi@ucsd.edu> (Steve Churchill)
#       Return code bug fixes.
#
#    <rik@kde.org> (Rik Hemsley)
#       Found STDIN bug.
#
# Changes:
#
# 1.3.2 Better handling of command line arguments to compiler.
#
#       If we aren't colorizing output, we just exec the compiler which
#       preserves the original STDOUT and STDERR.
#
#       Removed STDIN kludge. STDIN being passed correctly now.
# 
# 1.3.1 Added kludge to copy STDIN to the compiler's STDIN.
#
# 1.3.0 Now correctly returns (I hope) the return code of the compiler
#       process as its own.
# 
# 1.2.1 Applied patch to handle text similar to -DPACKAGE=\"Package\".
#
# 1.2.0 Added tty check. If STDOUT is not a tty, don't do color.
#
# 1.1.0 Added the "nocolor" option to turn off the color if the terminal type
#       ($TERM) is listed.
#
# 1.0.0 Initial Version

use strict;

use Term::ANSIColor;
use IPC::Open3;
use Cwd 'abs_path';

my(%nocolor, %colors, %compilerPaths);
my($unfinishedQuote, $previousColor);

sub initDefaults
{
   $nocolor{"dumb"} = "true";

   $colors{"srcColor"} = color("cyan");
   $colors{"introColor"} = color("blue");

   $colors{"warningFileNameColor"} = color("yellow");
   $colors{"warningNumberColor"}   = color("yellow");
   $colors{"warningColumnNumberColor"}   = color("yellow");
   $colors{"warningMessageColor"}  = color("yellow");

   $colors{"errorFileNameColor"} = color("bold red");
   $colors{"errorNumberColor"}   = color("bold red");
   $colors{"errorColumnNumberColor"}   = color("bold red");
   $colors{"errorMessageColor"}  = color("bold red");
}

sub loadPreferences
{
# Usage: loadPreferences("filename");

   my($filename) = @_;

   open(PREFS, "<$filename") || return;

   while(<PREFS>)
   {
      next if (m/^\#.*/);          # It's a comment.
      next if (!m/(.*):\s*(.*)/);  # It's not of the form "foo: bar".

      my $option = $1;
      my $value = $2;

      if ($option eq "nocolor")
      {
	 # The nocolor option lists terminal types, separated by
	 # spaces, not to do color on.
	 foreach my $term (split(' ', $value))
	 {
	    $nocolor{$term} = 1;
	 }
      }
      elsif (defined $colors{$option})
      {
	 $colors{$option} = color($value);
      }
      else
      {
	 $compilerPaths{$option} = $value;
      }
   }
   close(PREFS);
}

sub srcscan
{
# Usage: srcscan($text, $normalColor)
#    $text -- the text to colorize
#    $normalColor -- The escape sequence to use for non-source text.

# Looks for text between ` and ', and colors it srcColor.

   my($line, $normalColor) = @_;

   if (defined $normalColor)
   {
      $previousColor = $normalColor;
   }
   else
   {
      $normalColor = $previousColor;
   }

   my($srcon) = color("reset") . $colors{"srcColor"};
   my($srcoff) = color("reset") . $normalColor;

   $line = ($unfinishedQuote? $srcon : $normalColor) . $line;

   # These substitutions replaces `foo' with `AfooB' where A is the escape
   # sequence that turns on the the desired source color, and B is the
   # escape sequence that returns to $normalColor.

   my($lquote) = "\`|‘";
   my($lquotes) = "\`‘";
   my($rquote) = "\'|’";
   my($rquotes) = "\'’";

   # Handle multi-line quotes.
   if ($unfinishedQuote) {
      if ($line =~ s/^([^$rquotes]*?)($rquote)/$1$srcoff\'/)
      {
	 $unfinishedQuote = 0;
      }
   }
   if ($line =~ s/($lquote)([^$rquotes]*?)$/\`$srcon$2/)
   {
      $unfinishedQuote = 1;
   }

   # Single line quoting.
   #$line =~ s/\`(.*?)\'/\`$srcon$1$srcoff\'/g;
   $line =~ s/($lquote)(.*?)($rquote)/\`$srcon$2$srcoff\'/g;

   print($line, color("reset"));
}

#
# Main program
#

# Set up default values for colors and compilers.
initDefaults();

# Read the configuration file, if there is one.
my $configFile = $ENV{"HOME"} . "/.colorgccrc";
if (-f $configFile)
{
   loadPreferences($configFile);
}
elsif (-f '/etc/colorgcc/colorgccrc')
{
   loadPreferences('/etc/colorgcc/colorgccrc');
}

# Set our default output color.  This presumes that any unrecognized output
# is an error.
$previousColor = $colors{"errorMessageColor"};

# Figure out which compiler to invoke based on our program name.
$0 =~ m%.*/(.*)$%;
my $progName = $1 || $0;
my $compiler_pid;

# If called as "colorgcc", just filter STDIN to STDOUT.
if ($progName eq 'colorgcc')
{
   open(GCCOUT, "<&STDIN");
}
else
{
   # See if the user asked for a specific compiler.
   my $compiler;
   if (!defined($compiler = $compilerPaths{$progName}))
   {
      # Find our wrapper dir on the PATH and tweak the PATH to remove
      # everything up-to and including our wrapper dir.
      if ($0 =~ m#(.*)/#)
      {
	 # We were called with an explicit path, so trim that off the PATH.
	 my $find = $1;
	 $find = abs_path($1) unless $find =~ m#^/#;
	 $ENV{'PATH'} =~ s#.*(^|:)\Q$find\E(:|$)##;
      }
      else
      {
	 my(@dirs) = split(/:/, $ENV{'PATH'});
	 while (defined($_ = shift @dirs))
	 {
	    if (-x "$_/$progName")
	    {
	       $ENV{'PATH'} = join(':', @dirs);
	       last;
	    }
	 }
      }
      $compiler = $progName;
   }

   # Get the terminal type. 
   my $terminal = $ENV{"TERM"} || "dumb";

   # If it's in the list of terminal types not to color, or if
   # we're writing to something that's not a tty, don't do color.
   #if (! -t STDOUT || $nocolor{$terminal})
   if ($nocolor{$terminal})
   {
      exec $compiler, @ARGV
	 or die("Couldn't exec");
   }

   # Keep the pid of the compiler process so we can get its return
   # code and use that as our return code.
   $compiler_pid = open3('<&STDIN', \*GCCOUT, \*GCCOUT, $compiler, @ARGV);
}

# Colorize the output from the compiler.
while(<GCCOUT>)
{
   if (m#^(.+?\.[^:/ ]+):([0-9]+):([0-9]+)([:,] *)(.*)$#) # filename:lineno:colno:message
   {
      my $field1 = $1; # || "";
      my $field2 = $2; # || "";
      my $field3 = $3; # || "";
      my $sep = $4; # || "";
      my $field4 = $5; # || "";

      my ($c1, $c2, $c3, $c4);

      if (!$field4) {
         $c1 = $colors{"introColor"};
	 $c2 = $colors{"warningNumberColor"};
	 $c3 = $colors{"warningColumnNumberColor"};
	 $c4 = color("reset");
      }
      elsif ($field4 =~ m/warning:.*/)
      {
	 # Warning
         $c1 = $colors{"warningFileNameColor"};
	 $c2 = $colors{"warningNumberColor"};
	 $c3 = $colors{"warningColumnNumberColor"};
	 $c4 = $colors{"warningMessageColor"};
      }
      else 
      {
	 # Error
         $c1 = $colors{"errorFileNameColor"};
	 $c2 = $colors{"errorNumberColor"};
	 $c3 = $colors{"errorColumnNumberColor"};
	 $c4 = $colors{"errorMessageColor"};
      }
      print($c1, "$field1", color("reset"), ":");
      print($c2, "$field2", color("reset"), ":");
      print($c3, "$field3", color("reset"), "$sep");
      if ($field4) {
	 srcscan($field4, $c4);
      }
      print("\n");
   }
   elsif (m#^(.+?\.[^:/ ]+):([0-9]+)([:,] *)(.*)$#) # filename:lineno:message
   {
      my $field1 = $1; # || "";
      my $field2 = $2; # || "";
      my $field3 = ""; # || "";
      my $sep = $3; # || "";
      my $field4 = $4; # || "";

      my ($c1, $c2, $c3, $c4);

      if (!$field4) {
         $c1 = $colors{"introColor"};
	 $c2 = $colors{"warningNumberColor"};
	 $c4 = color("reset");
      }
      elsif ($field4 =~ m/warning:.*/)
      {
	 # Warning
         $c1 = $colors{"warningFileNameColor"};
	 $c2 = $colors{"warningNumberColor"};
	 $c4 = $colors{"warningMessageColor"};
      }
      else 
      {
	 # Error
         $c1 = $colors{"errorFileNameColor"};
	 $c2 = $colors{"errorNumberColor"};
	 $c4 = $colors{"errorMessageColor"};
      }
      print($c1, "$field1", color("reset"), ":");
      print($c2, "$field2", color("reset"), "$sep");
      if ($field4) {
	 srcscan($field4, $c4);
      }
      print("\n");
   }
   elsif (m/^(:.+`.*')$/) # filename:message:
   {
      srcscan($1, $colors{"warningMessageColor"});
      print("\n");
   }
   elsif (m/^(.*?):(.+):$/) # filename:message:
   {
      # No line number, treat as an "introductory" line of text.
      print($colors{"introColor"}, "$1:", color("reset"));
      srcscan($2, $colors{"introColor"});
      print($colors{"introColor"}, ":", color("reset"));
      print("\n");
   }
   elsif (m/^(.*)$/) # Anything else.
   {
      srcscan($1, undef);
      print("\n");
   }
}

if ($compiler_pid)
{
   # Get the return code of the compiler and exit with that.
   waitpid($compiler_pid, 0);
   exit ($? >> 8);
}
