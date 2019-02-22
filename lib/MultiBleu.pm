#!/usr/bin/env perl
#
# This file is part of moses.  Its use is licensed under the GNU Lesser General
# Public License version 2.1 or, at your option, any later version.

package MultiBleu;
# pragma

use strict;
use utf8;
binmode(STDOUT, ":utf8");

#------------------------------------------------------------------------------------------------
# 
use Exporter;


our @ISA = qw(Exporter);
our @EXPORT = qw( &bleuScore  );
our @EXPORT_OK = qw( );	
our $VERSION = '1.0';

BEGIN {
	
}

my $lowercase = 0;
my $separators=" .,:!?;()\"'";

# first arg is a tsv file name : the first column contain the hypothesis, the following cols the reference sentences
sub bleuScore {
	my $csvFile=shift;
	my $ref=shift; # the number of references. The tsv should contain $ref+1 col
	
	my @sentTuples; # list of tuple of sents. For each tuple, the first sent is the hypothesis, the following are the reference.


	if (-e $csvFile) {

		if ($csvFile =~ /.gz$/) {
			open(SENTS,"gzip -dc $csvFile|") or die "Can't read $csvFile";
		} else { 
			open(SENTS,$csvFile) or die "Can't read $csvFile";
		}
		while(<SENTS>) {
			chop;
			my @sentTuple=split(/\t/,$_);
			if ($ref > @sentTuple-1) {
				print STDERR "Every line should have ".($ref+1)." columns\n";
				return "Every line should have ".($ref+1)." columns. No score";
			};
			push @sentTuples, \@sentTuple;
		}
		close(SENTS);
	} else {
		return "File not found. No score";
	}

	my(@CORRECT,@TOTAL,$length_translation,$length_reference);

	foreach my $sentTuple (@sentTuples) {
		my $hypSent=$sentTuple->[0];
		$hypSent = lc if $lowercase;
		my @WORD = split(/[$separators]+/,$hypSent); # tokenization eliminates blank spaces and punctuation
		my %REF_NGRAM = ();
		my $length_translation_this_sentence = scalar(@WORD);
		my ($closest_diff,$closest_length) = (9999,9999);
		my @refSents=@{$sentTuple}[1..$ref];
		foreach my $reference (@refSents) {
	#      print "$s $_ <=> $reference\n";
			$reference = lc($reference) if $lowercase;
			my @WORD = split(/[$separators]+/,$reference);
			my $length = scalar(@WORD);
			my $diff = abs($length_translation_this_sentence-$length);
			if ($diff < $closest_diff) {
				$closest_diff = $diff;
				$closest_length = $length;
				# print STDERR "$s: closest diff ".abs($length_translation_this_sentence-$length)." = abs($length_translation_this_sentence-$length), setting len: $closest_length\n";
			} elsif ($diff == $closest_diff) {
				$closest_length = $length if $length < $closest_length;
				# from two references with the same closeness to me
				# take the *shorter* into account, not the "first" one.
			}
			for(my $n=1;$n<=4;$n++) {
				my %REF_NGRAM_N = ();
				for(my $start=0;$start<=$#WORD-($n-1);$start++) {
					my $ngram = "$n";
					for(my $w=0;$w<$n;$w++) {
						$ngram .= " ".$WORD[$start+$w];
					}
					$REF_NGRAM_N{$ngram}++;
				}
				foreach my $ngram (keys %REF_NGRAM_N) {
					if (!defined($REF_NGRAM{$ngram}) ||
						$REF_NGRAM{$ngram} < $REF_NGRAM_N{$ngram}) {
						$REF_NGRAM{$ngram} = $REF_NGRAM_N{$ngram};
		#	    		print "$i: REF_NGRAM{$ngram} = $REF_NGRAM{$ngram}<BR>\n";
					}
				}
			}
		}
		$length_translation += $length_translation_this_sentence;
		$length_reference += $closest_length;
		for(my $n=1;$n<=4;$n++) {
			my %T_NGRAM = ();
			for(my $start=0;$start<=$#WORD-($n-1);$start++) {
				my $ngram = "$n";
				for(my $w=0;$w<$n;$w++) {
					$ngram .= " ".$WORD[$start+$w];
				}
				$T_NGRAM{$ngram}++;
			}
			foreach my $ngram (keys %T_NGRAM) {
				$ngram =~ /^(\d+) /;
				my $n = $1;
					# my $corr = 0;
		#	print "$i e $ngram $T_NGRAM{$ngram}<BR>\n";
				$TOTAL[$n] += $T_NGRAM{$ngram};
				if (defined($REF_NGRAM{$ngram})) {
					if ($REF_NGRAM{$ngram} >= $T_NGRAM{$ngram}) {
						$CORRECT[$n] += $T_NGRAM{$ngram};
							# $corr =  $T_NGRAM{$ngram};
		#	    print "$i e correct1 $T_NGRAM{$ngram}<BR>\n";
					}
					else {
						$CORRECT[$n] += $REF_NGRAM{$ngram};
							# $corr =  $REF_NGRAM{$ngram};
		#	    print "$i e correct2 $REF_NGRAM{$ngram}<BR>\n";
					}
				}
					# $REF_NGRAM{$ngram} = 0 if !defined $REF_NGRAM{$ngram};
					# print STDERR "$ngram: {$s, $REF_NGRAM{$ngram}, $T_NGRAM{$ngram}, $corr}\n"
			}
		}
	}

	my $brevity_penalty = 1;
	my $bleu = 0;

	my @bleu=();

	for(my $n=1;$n<=4;$n++) {
		if (defined ($TOTAL[$n])){
			$bleu[$n]=($TOTAL[$n])?$CORRECT[$n]/$TOTAL[$n]:0;
		# print STDERR "CORRECT[$n]:$CORRECT[$n] TOTAL[$n]:$TOTAL[$n]\n";
		}else{
			$bleu[$n]=0;
		}
	}

	
	if ($length_reference==0){
		my $result=sprintf "BLEU = 0, 0/0/0/0 (BP=0, ratio=0, hyp_len=0, ref_len=0)\n";
		return ($result);
	}

	if ($length_translation<$length_reference) {
	  $brevity_penalty = exp(1-$length_reference/$length_translation);
	}
	$bleu = $brevity_penalty * exp((my_log( $bleu[1] ) +
					my_log( $bleu[2] ) +
					my_log( $bleu[3] ) +
					my_log( $bleu[4] ) ) / 4) ;
	my $result=sprintf "BLEU = %.2f, %.1f/%.1f/%.1f/%.1f (BP=%.3f, ratio=%.3f, hyp_len=%d, ref_len=%d)\n",
		100*$bleu,
		100*$bleu[1],
		100*$bleu[2],
		100*$bleu[3],
		100*$bleu[4],
		$brevity_penalty,
		$length_translation / $length_reference,
		$length_translation,
		$length_reference;
		
	return $result;


	sub my_log {
	  return -9999999999 unless $_[0];
	  return log($_[0]);
	}
}

1;
