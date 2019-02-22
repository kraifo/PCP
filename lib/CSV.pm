#!/usr/bin/perl

package CSV;

# pragma
use strict;
use utf8;

# modules
use Encode;
use IO::Handle;

STDOUT->autoflush();


#******************************************************* Variables globales privées

my $defaultEncoding="iso-8859-1";
my $defaultSep="\t";
my $defaultTitle=0;
my $defaultKey=0;

#******************************************************** Méthodes

# constructeur de la classe
sub new {
	my $class=shift;
	my $this={};
	
	$this->{encoding}=$defaultEncoding;
	$this->{title}=$defaultTitle;
	$this->{sep}=$defaultSep;
	$this->{key}=$defaultKey;
	$this->{data}=[];
	$this->{verbose}=1;
	
	bless($this,$class);
	return $this;
	
}

# lecture d'un fichier CSV
# Exemple : $csv->readCsv();

sub readCSV {
	my $this=shift;
	my $fileName=shift;
	my $n=0;
	
	# ouverture du fichier et lecture ligne par ligne
	open(IN,"<:encoding(".$this->{encoding}.")",$fileName) or die "Impossible de lire $this->{fileName}\n";
	while (my $line=<IN>) {
		chomp $line;
		
		# découpage en colonnes
		my @cols=split(/$this->{sep}/,$line);
		# enregistrement de la liste des valeurs
		push(@{$this->{data}},\@cols);
		$n++;
	}
	close(IN);
	
	$this->{verbose} && print "$n lignes lues\n";

}

# Tri du tableau
# Exemple : $csv->sortCSV(9,"n-desc"); # tri de la 9ème colonne numérique décroissant

sub sortCSV {
	my $this=shift;
	my $numCol=shift;
	my $order=shift;
	
	my @tab=@{$this->{data}};	# pas efficace mais permet de ne pas dépiler la ligne de titre
	
	my @result;
	my $titleLine;
	
	# on décale la ligne de titre
	if ($this->{title}) {
		$titleLine=shift(@tab);
	}
	
	if ($order eq "n-asc") {
		@result=sort {$a->[$numCol] <=> $b->[$numCol]} @tab;
	} elsif ($order eq "n-desc") {
		@result=sort {$b->[$numCol] <=> $a->[$numCol]} @tab;
	} elsif ($order eq "a-asc") {
		@result=sort {$a->[$numCol] cmp $b->[$numCol]} @tab;
	} elsif ($order eq "a-desc") {
		@result=sort {$b->[$numCol] cmp $a->[$numCol]} @tab;
	} else {
		print "$order : invalid order name\n";
	}
	# on remet la ligne de titre
	if ($this->{title}) {
		unshift(@result,$titleLine);
	}
	
	$this->{data}=\@result;
}


# Ajout d'une colonne
# Exemple : $csv->addColumn(\@newCol)
sub addColumn {
	my $this=shift;
	my $refCol=shift;
	
	if (@{$this->{data}} != @{$refCol}) {
		$this->{verbose} && print "Attention nombre de lignes différent\n";
		return 0;
	}
	
	# parcours du tableau
	for (my $line=0;$line<@{$this->{data}};$line++) {
		push(@{$this->{data}[$line]},$refCol->[$line]);
	}
	return 1;
}

# Ecriture vers un nouveau fichier CSV avec les données courantes, pour une sélection de colonne donnée
# Exemple : $csv->writeCSV("test.csv",[1,2]);

sub writeCSV {
	my $this=shift;
	my $newFileName=shift;
	my $refCols=shift;
	
	open(OUTPUT,">:encoding(".$this->{encoding}.")",$newFileName) or die "impossible d'écrire sur $newFileName";
	foreach my $line (@{$this->{data}}) {
		my @currentLine;
		foreach my $col (@{$refCols}) {
			push (@currentLine,$line->[$col]);
		}
		print OUTPUT join($this->{sep},@currentLine)."\n";
	}
	close(OUTPUT);
	return 1;
}

# Extrait un hachage à partir d'une table
# Exemple : %hash=$csv->CSV2hash([3,4],"\t") permet de créer un hachage, dont les clés sont prises dans la colonne $this->key et les valeurs dans les colonnes d'index 2 et 4, concaténées avec "\t".

sub CSV2hash {
	my $this=shift;
	my $refCols=shift;
	my $sep=shift;
	
	my %result;
	
	my $firstLoop=1;
	# parcours des lignes du tableau
	foreach my $line (@{$this->{data}}) {
		# on saute la ligne de titre
		if ($this->{title} && $firstLoop) {
			$firstLoop=0;
			next;
		}
		$firstLoop=0;
		
		# on construit la ligne courante à partir des index présents dans @{$refCols}
		my @currentLine;
		foreach my $col (@{$refCols}) {
			push (@currentLine,$line->[$col]);
		}
		
		# on contrôle si la clé a déjà été utilisé
		if (exists($result{$line->[$this->{key}]})) {
			$this->{verbose} && print "Attention clé répétée : une ligne sera perdue\n";
		}
		# on ajoute le couple clé ->valeur, en tenant compte de la valeur de $sep
		# cas 1 : la valeur est le résultat de la concaténation des colonnes
		if ($sep) {
			$result{$line->[$this->{key}]}=join($sep,@currentLine);
		# cas 2 : on laisse une référence vers la liste
		} else {
			$result{$line->[$this->{key}]}=\@currentLine;
		}
	}
	return %result;
}


1;
