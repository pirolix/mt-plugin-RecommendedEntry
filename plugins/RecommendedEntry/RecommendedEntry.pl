package MT::Plugin::RecommendedEntry;
#   RecommendedEntry - *TINY* Recommendation engine for MovableType
#           Original Copyright (c) 2007 Piroli YUKARINOMIYA
#           Open MagicVox.net - http://www.magicvox.net/
#           @see http://www.magicvox.net/archive/2007/02121659/

use strict;

use vars qw( $MYNAME $VERSION );
$MYNAME = 'RecommendedEntry';
$VERSION = '1.00';

use base qw( MT::Plugin );
my $plugin = new MT::Plugin ({
        name => $MYNAME,
        version => $VERSION,
        author_name => 'Piroli YUKARINOMIYA',
        author_link => 'http://www.magicvox.net/?'. $MYNAME,
        doc_link => 'http://www.magicvox.net/archive/2007/02121659/?'. $MYNAME,
        description => <<HTMLHEREDOC,
Enable to create recommendations of the other articles
by tracking the incomming and outgoing flow of visitors.
HTMLHEREDOC
});
MT->add_plugin( $plugin );

sub instance { $plugin }

########################################################################
use MT::Template::Context;

### MTUseRecommendedEntry; Embed a PHP code to setup the MTRecommendedEntry
MT::Template::Context->add_tag( UseRecommendedEntry => \&use_recommended_entry );
sub use_recommended_entry {
    my( $ctx, $args ) = @_;
#
    # Entry ID
    my $entry = $ctx->stash( 'entry' )
        or return $ctx->error( "Can't find an entry. Use on the context MTEntry* tag." );
    my $entry_id = $entry->id;
    my $blog_id = $entry->blog_id;

    my $all_entry_index = undef;
    # template
    if( defined( my $template_name = $args->{template} )) {
        require MT::Template;
        my $tmpl = MT::Template->load({ blog_id => $blog_id, name => $template_name })
            or return $ctx->error( "$MYNAME: specified index template was not found - $template_name" );
        $all_entry_index = $tmpl->outfile;
        unless( $all_entry_index =~ m!^/! )
        {
            # Retrieving site path of this blog
            require MT::Blog;
            my $blog = MT::Blog->load( $blog_id )
                or return $ctx->error( "$MYNAME: invalid blog id" );
            my $site_path = $blog->site_path;
            $site_path .= '/' unless $site_path =~ m!/$!;
            $all_entry_index = $site_path. $all_entry_index;
        }
    }
    # index
    $all_entry_index = $args->{index}
        if defined $args->{index};
    # must be required
    defined $all_entry_index
        or return $ctx->error( "<index> or <template> param must be required." );
    -f $all_entry_index
        or return $ctx->error( "Can't find the all entries index - $all_entry_index" );

    # datapath
    my $datapath = $args->{datapath}
        or return $ctx->error( "<datapath> param must be required." );
    -d $datapath
        or return $ctx->error( "Can't find the directory specified with <datapath> - $datapath" );

    # cookie_expire
    my $cookie_expire = $args->{cookie_expire} || 60 * 60 * 24 * 30;#sec
    # cookie_name
    my $cookie_name = $args->{cookie_name} || 'mtrcmnd_eid';

    my $php_code = <<'PHPHEREDOC';
<?php
////////////////////////////////////////////////////////////////////////
// MT%%PROG_NAME%%
// @see http://www.magicvox.net/archive/2007/02121659/?%%PROG_NAME%%
@include( '%%ALL_ENTRY_INDEX%%' );
function %%PROG_NAME%%_getEntryData( $eid ) {
	$entries = %%PROG_NAME%%_getAllEntries();
	foreach( $entries as $index => $value )
	if( $value['eid'] == $eid )
		return $value;
	return null;
}

function %%PROG_NAME%%_updateIndexFile( $eid_updated, $eid, $direction ) {
	$filename = '%%DATA_PATH%%';
	is_dir( $filename ) || mkdir( $filename );
	$filename .= '/'. substr( $eid_updated, -1 );
	is_dir( $filename ) || mkdir( $filename );
	$filename .= sprintf( '/%d.txt', $eid_updated);
	file_exists( $filename ) || touch( $filename );
	$fp = @fopen( $filename, 'r+' );
	if( $fp ) {
		if( flock( $fp, LOCK_EX | LOCK_NB )) {
			$ret = '';
			$not_found = 1;
			while( !feof( $fp ) && ( $buf = fgets( $fp ))) {
				list( $_eid, $_n0, $_n1 ) = split( "[\t\r\n]", $buf );
				if( $eid == $_eid ) {
					$not_found = 0; $direction ? $_n1++ : $_n0++;
				}
				$ret .= sprintf( "%d\t%d\t%d\n", $_eid, $_n0, $_n1 );
			}
			if( $not_found )
				$ret .= sprintf( "%d\t%d\t%d\n", $eid, 1 - $direction, $direction);
			rewind( $fp );
			fwrite( $fp, $ret, strlen( $ret ));
		}
		fclose( $fp );
	}
}

function %%PROG_NAME%%_incoming() {
	$eid_prev = $_COOKIE['%%COOKIE_NAME%%'];
	if( isset( $eid_prev )) {
		if( $eid_prev != %%ENTRY_ID%% && %%PROG_NAME%%_getEntryData( $eid_prev )) {
			%%PROG_NAME%%_updateIndexFile( %%ENTRY_ID%%, $eid_prev, 0 /*incoming_from*/ );
			%%PROG_NAME%%_updateIndexFile( $eid_prev, %%ENTRY_ID%%, 1 /*outgoing_to*/ );
		}
	} else {
		%%PROG_NAME%%_updateIndexFile( %%ENTRY_ID%%, %%ENTRY_ID%%, 0 /*incoming_from*/ );
	}
}
%%PROG_NAME%%_incoming();

function %%PROG_NAME%%_outgoing() {
	setcookie( '%%COOKIE_NAME%%', %%ENTRY_ID%%, time() + %%COOKIE_EXPIRE%%, '/' );
}
%%PROG_NAME%%_outgoing();

function %%PROG_NAME%%_initialize( $mode = 0 ) {
	global $%%PROG_NAME%%_table;
	$%%PROG_NAME%%_table = array();
	$filename = '%%DATA_PATH%%/'. substr( '%%ENTRY_ID%%', -1 ). '/%%ENTRY_ID%%.txt';
	$fp = @fopen( $filename, 'r' );
	if( $fp ) {
		if( flock( $fp, LOCK_SH | LOCK_NB )) {
			while( !feof( $fp ) && ( $buf = fgets( $fp ))) {
				list( $_eid, $_n0, $_n1 ) = split( "[\t\r\n]", $buf );
				if( %%ENTRY_ID%% == $_eid ) continue;
				else if( $mode == 1 ) $%%PROG_NAME%%_table{$_eid} = $_n0;
				else if( $mode == 2 ) $%%PROG_NAME%%_table{$_eid} = $_n1;
				else $%%PROG_NAME%%_table{$_eid} = $_n0 + $_n1;
			}
			arsort( $%%PROG_NAME%%_table, SORT_NUMERIC );
		}
		fclose( $fp );
	}
}

function %%PROG_NAME%%_GetEntry( $_index ) {
	global $%%PROG_NAME%%_table;
	foreach( $%%PROG_NAME%%_table as $eid => $count ) {
		if( --$_index ) continue;
		$entry = %%PROG_NAME%%_getEntryData( $eid );
		if( $entry )
			$entry['count'] = $count;
		return $entry;
	}
}
?>
PHPHEREDOC
    chomp $php_code;

    # Replace the path of the data file in PHP code
    $php_code =~ s/%%PROG_NAME%%/$MYNAME/g;
    $php_code =~ s/%%ENTRY_ID%%/$entry_id/g;
    $php_code =~ s/%%ALL_ENTRY_INDEX%%/$all_entry_index/g;
    $php_code =~ s/%%DATA_PATH%%/$datapath/g;
    $php_code =~ s/%%COOKIE_EXPIRE%%/$cookie_expire/g;
    $php_code =~ s/%%COOKIE_NAME%%/$cookie_name/g;
    $php_code;
}



### MTRecommendedEntries
MT::Template::Context->add_container_tag( RecommendedEntries => \&recommended_entries );
sub recommended_entries
{
    my( $ctx, $args, $cond ) = @_;
#
    my $mode = $args->{mode} || 0;
    my $offset = $args->{offset} || 0;
    my $count = $args->{count} || 10;
#
    my $builder = $ctx->stash( 'builder' );
    my $tokens = $ctx->stash( 'tokens' );
    defined( my $out = $builder->build( $ctx, $tokens, $cond ))
        or return $ctx->error( $builder->errstr );

    my $php_code = <<"PHPHEREDOC";
<?php
    ${MYNAME}_initialize( $mode );
    for( \$${MYNAME}_index = $offset + 1; \$${MYNAME}_index <= $offset + $count; \$${MYNAME}_index++ ) {
        \$${MYNAME}_entry = ${MYNAME}_GetEntry( \$${MYNAME}_index );
        if( \$${MYNAME}_entry ) { ?>
$out
<?php    }
    }
?>
PHPHEREDOC
    chomp $php_code;
    $php_code;
}



### MTRecommendedEntryParam
MT::Template::Context->add_tag( RecommendedEntryParam => \&recommended_entry_param );
sub recommended_entry_param {
    my( $ctx, $args ) = @_;
#
    # name
    my $name = $args->{name}
        or return $ctx->error( '<name> param must be required.' );
    "<?php echo \$${MYNAME}_entry['$name']; ?>";
}

1;
__END__
########################################################################
# '07/02/12 1.00  ‰”ÅŒöŠJ
