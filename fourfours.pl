#!/usr/bin/perl

# (c) 2013 Alex Bligh
# Released under the Artistic Licence

use strict;
use warnings;
use POSIX;
use Getopt::Long;
use FindBin;

my %cachedeval;
my %cachedfactorial;

my $option_digit = 4;
my $option_count = 4;
my $option_decimal = 0;
my $option_recurring = 0;
my $option_sqrt = 0;
my $option_power = 0;
my $option_factorial = 0;
my $option_multidigit = 0;
my $option_all = 0;

my $precision = 0.0000001;
my $maxfactorial = 12;
my $bigint=2**63;
my $largestresult=2**32;

my @operators;

sub Syntax
{
    print STDERR <<STOP;
Usage: $FindBin::Script [options] [COUNT [DIGIT]]

Options:
  -d, --decimal    Allow decimals
  -r, --recurring  Allow recurring decimals
  -s, --sqrt       Allow square roots
  -p, --power      Allow X to the power Y
  -f, --factorial  Allow factorials
  -m, --multidigit Allow multidigit numbers
  -x, --xmas       Turn on all options
  -a, --all        Print all answers (not just positive integers)
  -h, --help       Print this message

STOP
return;
}

sub ParseOptions
{
    if (!GetOptions (
             "decimal|d" => \$option_decimal,
             "recurring|r" => \$option_recurring,
             "sqrt|s" => \$option_sqrt,
             "power|p" => \$option_power,
	     "factorial|f" => \$option_factorial,
	     "multidigit|m" => \$option_multidigit,
	     "all|a" => \$option_all,
	     "xmas|x" => sub {
		 $option_decimal = 1;
		 $option_recurring = 1;
		 $option_sqrt = 1 ;
		 $option_power = 1;
		 $option_factorial = 1;
		 $option_multidigit = 1;
	     },
             "help|h" => sub {
		 Syntax();
		 exit(0);
	     }
        ))
    {
        Syntax();
        die "Bad options";
    }

    $option_count = shift (@ARGV) if ($#ARGV >= 0);
    
    $option_digit = shift (@ARGV) if ($#ARGV >= 0);

    die ("Bad options") unless ($#ARGV == -1);
}

# As I want to run on a Mac with no Math::Round or CPAN access
sub iround
{
    return (floor(0.5+shift @_));
}

sub iisint
{
    my $i = shift @_;
    return (abs(iround($i)-$i)<$precision);
}

sub iclean
{
    my $i = shift @_;
    return undef unless(defined($i));
    return (abs(iround($i)-$i)<$precision)?(floor(0.5+$i)):$i;
}

sub numerically
{
    return ($a<=>$b);
}

sub CachedFactorial
{
    my $s = shift @_;
    return $cachedfactorial{$s} if (exists($cachedfactorial{$s}));

    unless (($s>0) && (iisint($s)) && ($s<=$maxfactorial))
    {
	$cachedfactorial{$s} = undef;
	return undef;
    }
    $s = iround($s);

    my $f = $s;
    for (my $i = $s-1 ; $i >0 ; $i--)
    {
	if (exists($cachedfactorial{$i}))
	{
	    $f *= $cachedfactorial{$i};
	    last;
	}
	else
	{
	    $f *= $i;
	    if ($f > $bigint)
	    {
		$f = undef;
		last;
	    }
	}
    }

    $cachedfactorial{$s} = $f;
    return $f;
}
    
sub CachedEval
{
    my $s = shift @_;
    return $cachedeval{$s} if (exists($cachedeval{$s}));
    my $e = eval($s);
    if ($@)
    {
	$e = undef;
    }
    else
    {
	$e = iclean ($e);
    }
    $cachedeval{$s}=$e;
    return $e;
}

sub UseIfBetter
{
    my $ref = shift @_;
    my $formula = shift @_;
    if (!defined($$ref))
    {
	$$ref = $formula;
	return;
    }
    my $rl = length ($$ref);
    my $fl = length ($formula);
    $$ref = $formula if (($fl < $rl) || (($fl == $rl) && ($formula lt $$ref)));
}

sub DoUnaries
{
    my $rbest = shift @_;
    my $r = shift @_;
    my $formula = shift @_;
    my $digits = shift @_;
    my $iteration = (shift @_) -1;
    return if ($iteration<0);

    # No point in any of these unaries on <=0
    return if ($r<=0);

    # Don't bother with square roots of non-integers
    if ($option_sqrt && iisint($r))
    {
	my $sqrt = CachedEval(sqrt($r));
	# We know that the smaller atom if it has brackets only has one pair of brackets
	my $nformula = "sqrt( $formula )";
	$nformula = "sqrt $formula" if ($formula =~ /^\s*\(/);
	UseIfBetter ( \$$rbest{$digits}{$sqrt}, $nformula);
	DoUnaries ($rbest, $sqrt, $nformula, $digits, $iteration);
    }
    
    if ($option_factorial && iisint($r) && ($r<10))
    {
	my $fact = CachedFactorial($r);
	if(defined($fact))
	{
	    UseIfBetter ( \$$rbest{$digits}{$fact}, "$formula!");
	    DoUnaries ($rbest, $fact, "$formula!", $digits, $iteration);
	}
    }
}

sub CalcOptions
{
    my %best;

    my $ndigits = shift @_;
    my $maxunary = $ndigits+1;

    for (my $digits = 1; $digits <= $ndigits; $digits++)
    {
	if (($digits == 1) || $option_multidigit)
	{
	    UseIfBetter ( \$best{$digits}{ $option_digit x $digits + 0}, $option_digit x $digits);

	    if ($option_decimal)
	    {
		for (my $i = 0 ; $i < $digits ; $i++)
		{
		    my $s = ( $option_digit x $i ) . "." . ($option_digit x ($digits-$i));
		    UseIfBetter ( \$best{$digits}{$s+0}, $s);
		}
	    }
	    
	    if ($option_recurring)
	    {
		my $rf = ($option_digit x ($digits-1)) . "." . $option_digit."~";
		my $rv = $option_digit * (10**($digits-1)) / 9;
		UseIfBetter ( \$best{$digits}{$rv}, $rf);
	    }
	}

	# Pick the index after which we will split
	for ( my $i = 0 ; $i < $digits-1 ; $i++ )
	{
	    my $l = $i + 1;
	    my $r = ($digits-1) - $i;
	    
	    foreach my $lr (sort keys %{ $best{$l} })
	    {
		foreach my $rr (sort keys %{ $best {$r} })
		{
		    foreach my $op (@operators)
		    {
			my $formula = "( ".$best{$l}{$lr}."  $op ".$best{$r}{$rr}." )";
			my $ev = CachedEval ("$lr $op $rr");
			if(defined($ev) && (($digits<$ndigits) || iisint($ev)))
			{
			    UseIfBetter(\$best{$digits}{$ev}, $formula);
			}
		    }
		}
	    }
	}
	
	# Now apply the unary operators to each of the 'best'
	foreach my $r (sort numerically keys %{ $best{$digits} } )
	{
	    my $formula = $best{$digits}{$r};
	    DoUnaries (\%best, $r, $formula, $digits, $maxunary);
	}

	# Lastly apply unary minus, which can only be applied once
	foreach my $r (sort numerically keys %{ $best{$digits} } )
	{
	    UseIfBetter ( \$best{$digits}{-$r}, "-".$best{$digits}{$r});
	}
    }

    my $hpint = 0;
    printf ("\n%d Digits:\n", $ndigits);
    foreach my $r (sort numerically keys %{ $best{$ndigits} } )
    {
	my $pint = iisint($r) && ($r>=0) && ($r<$largestresult);
	if ($pint && ($r>=1))
	{
	    $hpint = $r if ($r == $hpint+1);
	}
	if ($option_all || $pint)
	{
	    my $f = $best{$ndigits}{$r};
	    $f=~s/^\(\s*(.*)\s*\)$/$1/g;
	    printf "$r = $f\n", 
	}
    }
    printf "\nGot all the integers between 1 and %d\n", $hpint;
}

ParseOptions;

@operators = ( '*', '/', '+', '-' );
push @operators, '**' if ($option_power);

CalcOptions($option_count);
