#!/usr/bin/perl

use strict;
use warnings;

ACXSync->new;

package MainFrame;

use Wx qw[:everything];
use base qw(Wx::Frame);
use strict;
use File::Slurp qw/read_file/;
use JSON qw/decode_json/;

use constant _TABS => [
    [ 'video_panel', 'Video', 3, 1 ],
    [ 'audio_panel', 'Audio', 3, 1 ],
    [ 'settings_panel', 'Settings', 2, 4 ],
    [ 'processing_panel', 'Process', 2, 2 ],
];

use constant _LAYOUT => {
    video_panel => [
        [ 'TextCtrl::videoFile', wxID_ANY, '', wxDefaultPosition, [200, 34] ],
        [ 'Button::doLoadVideo', wxID_ANY, 'Load' ],
        [ 'Button::doPlayVideo', wxID_ANY, 'Play' ],
    ],
    audio_panel => [
        [ 'TextCtrl::audioFile', wxID_ANY, '', wxDefaultPosition, [200, 34] ],
        [ 'Button::doLoadAudio', wxID_ANY, 'Load' ],
        [ 'Button::doViewWaveform', wxID_ANY, 'View' ],
    ],
    settings_panel => [
        [ 'StaticText::thresholdLabel', wxID_ANY, 'Threshold (LUFS):' ],
        [ 'TextCtrl::thresholdValue', wxID_ANY, '' ],

        [ 'StaticText::loudnessLabel', wxID_ANY, 'Loudness (LUFS):' ],
        [ 'TextCtrl::loudnessValue', wxID_ANY, '' ],

        [ 'StaticText::clapTimestampLabel', wxID_ANY, 'Clap timestamp (s):' ],
        [ 'TextCtrl::clapTimestampValue', wxID_ANY, '' ],

        [ 'Button::getLoudnessData', wxID_ANY, 'Get loudness data' ],
        [ 'Button::saveSettings', wxID_ANY, 'Use' ],
    ],
    processing_panel => [
        [ 'StaticText::outFileNameLabel', wxID_ANY, 'Output file:' ],
        [ 'TextCtrl::outFileName', wxID_ANY, './output.mp4', wxDefaultPosition, [120, 34] ],

        [ 'Button::doProcess', wxID_ANY, 'Process', wxDefaultPosition, [120, 34] ],
        [ 'Button::playProcessed', wxID_ANY, 'Play', wxDefaultPosition, [120, 34] ],
    ],
};

sub new {
    my( $self, $title ) = @_;

    $self = $self->SUPER::new(
        undef,
        -1,
        $title,
        wxDefaultPosition,
        Wx::Size->new(400, 300),
        wxDEFAULT_DIALOG_STYLE,
        ''
    );

    $self->{main_sizer}  = Wx::BoxSizer->new(wxHORIZONTAL);

    $self->createLayout('main_sizer');

    return $self;

}

sub createLayout {
    my ( $self, $sizer ) = @_;

    $self->readConfig('./ff_conf.json');
    $self->createTabs($sizer);
    $self->createSettings;

    $self->{ status_bar } = Wx::StatusBar->new($self, wxID_ANY, wxSB_NORMAL, '');
    $self->{ status_bar }->SetFieldsCount(1);

    $self->SetStatusBar( $self->{ status_bar } );
    $self->SetSizer( $self->{ $sizer } );

    $self->setStatusText;

    $self->Layout;
}

sub setStatusText {
    my ( $self ) = @_;

    $self->{ status_text } = sprintf "Threshold: %.1f LUFS\tLoudness: %.1f LUFS",
        $self->{ Settings }->{ thresholdValue },
        $self->{ Settings }->{ loudnessValue };

    $self->{ status_bar }->SetStatusText($self->{ status_text }, 0);
}

sub createWidgets {
    my ($self, $tab_name) = @_;
    my $layout = _LAYOUT()->{ $tab_name };

    for my $desc ( @$layout ) {
        my ($class, $name) = split /::/, shift @$desc;
        my $wxClass = 'Wx::' . $class;

        $self->{ $name } = eval { $wxClass->new( $self->{ $tab_name }->{ page }, @$desc ) };

        $self->BtnEvent( $name ) if $class eq 'Button';
        $self->{ $tab_name }->{ sizer }->Add($self->{ $name }, 0, wxALIGN_CENTER_VERTICAL|wxALIGN_RIGHT, 0);
    }
}

sub createTabs {
    my ( $self, $sizer_name ) = @_;
    my $book = Wx::Notebook->new($self, wxID_ANY);

    for my $tab ( _TABS()->@* ) {
        my ($tab_name, $tab_label, $cols, $rows) = @$tab;

        $self->{ $tab_name } = {};
        $self->{ $tab_name }->{ sizer } = Wx::FlexGridSizer->new($rows, $cols, 10, 5);
        $self->{ $tab_name }->{ page  } = Wx::Panel->new($book, wxID_ANY);
        $self->{ $tab_name }->{ page  }->SetSizer($self->{ $tab_name }->{ sizer });

        $book->AddPage($self->{ $tab_name }->{ page }, $tab_label);

        $self->createWidgets( $tab_name );
    }

    $self->{ $sizer_name }->Add( $book, 1, wxEXPAND, 0 );
}

sub saveSettings {
    my ( $self ) = @_;

    map { $self->{ Settings }->{ $_ } = $self->{ $_ }->GetValue } keys $self->{ Settings }->%*;

    $self->setStatusText;
    $self->createSettings;
}

sub createSettings {
    my ( $self ) = @_;

    my ($t, $l) = $self->{ Conf }{ audio }{ lra }->@*;

    for my $field ( keys $self->{ Settings }->%* ) {
        $self->{ $field }->Clear;
        $self->{ $field }->WriteText( sprintf( '%.1f', $self->{ Settings }->{ $field } ) );
    }
}

sub readConfig {
    my ( $self, $path ) = @_;
    my $config = read_file( $path );

    $self->{ Conf } = decode_json( $config );

    my ($t, $l) = $self->{ Conf }{ audio }{ lra }->@*;

    $self->{ Settings } = {
        thresholdValue      => $t,
        loudnessValue       => $l,
        clapTimestampValue  => 5.0, # default
    };
}

sub doProcess {
    my ( $self ) = @_;
    my ($v, $a) = map { $self->{ Conf }->{$_} } qw/video audio/;

    my $to = $self->{ Settings }->{ clapTimestampValue };
    my $c_filters = $a->{ filters };

    my @filters;

    for my $f_name ( keys %$c_filters) {
        for my $f_params ( @{ $c_filters->{ $f_name } } ) {
            push @filters, $f_name . '=' . join ':', map { $_ . '=' . $f_params->{$_} } keys %$f_params;
        }
    }

    my $v_opts = sprintf("-c:v %s -b:v %s -vf fps=%s", map { $v->{$_} } qw/codec bitrate framerate/);
    my $a_opts = sprintf("-c:a %s -b:a %s", map { $a->{$_} } qw/codec bitrate/);

    my $tmp = "/tmp/$0.$$";
    my $aud = $self->{ audioFile }->GetValue;
    my $vid = $self->{ videoFile }->GetValue;

    my $ac = $self->_getClapTimestamp( $aud, $to );
    my $vc = $self->_getClapTimestamp( $vid, $to );

    my $ta = sprintf( "%.2f", $ac - $vc + $to );

    my $filters = [
        @filters,
        'agate=detection=rms:attack=150:release=150:threshold='
            . sprintf('%.3f', 10 ** ($self->{ Settings }{ thresholdValue } / 20)),

        'acompressor=attack=5:release=50:ratio=2:makeup=2:threshold='
            . sprintf('%.3f', 10 ** ($self->{ Settings }{ loudnessValue  } / 20)),

        'alimiter=limit=0.7:level=false',
    ];

    my $af = join ',', @$filters;

    $self->_ff( "-ss $ta -i \"$aud\" -ac 1 -af $af $tmp.1.wav");

    my $name = $self->{ outFileName }->GetValue;
    my $data = $self->_getLoudnessData("$tmp.1.wav", $to);

    my $loud = join ':', map { $_ . '=' . $data->{ $_ } } keys %$data;

    $self->_ff(
        "-i $tmp.1.wav -ac 1 -af loudnorm=dual_mono=true:i=-19.0:lra=6.0:tp=-4.0:$loud,aresample=resampler=soxr:out_sample_rate=48000:precision=28 $tmp.2.wav",
        "-ss $to -i \"$vid\" -c copy -an $tmp.1.mp4",
        "-y -i $tmp.1.mp4 -i $tmp.2.wav $v_opts $a_opts $name",
    );
}

sub _ff {
    my $self = shift;
    my @res;

    $self->{ status_bar }->SetStatusText("Processing...", 0);

    for my $cmd (@_) {
        eval {
            local $/ = "\r";
            open FH, '-|', 'ffmpeg ' . $cmd . ' 2>&1';

            while (<FH>) {
                chomp;
                push @res, $_;

                if ( m/frame=\s+([0-9]+).+time=(\d\d\:\d\d:\d\d\.\d\d)/ ) {
                    $self->{ status_bar }->SetStatusText("Frame: $1\tTime: $2", 0);
                }
            }
            close FH;
        };
    }

    $self->setStatusText;

    return join "\n", @res;
}

sub doViewWaveform {
    my ( $self ) = @_;

    my $file = $self->{ audioFile }->GetValue;
    my $img  = "/tmp/$0.$$.png";

    $self->{ status_bar }->SetStatusText('Rendering Waveform...', 0);

    $self->_ff( "-i \"$file\" -filter_complex \"compand,showwavespic=s=640x480::split_channels=1\" -frames:v 1 $img" );

    my $viewer = ImgViewer->new( $self, $self->{ audioFile }->GetValue, $img );

    $self->setStatusText;
    $viewer->Show;
}

sub doPlayVideo {
    my ( $self ) = @_;

    $self->_playVideo( $self->{ videoFile }->GetValue );
}

sub playProcessed {
    my ( $self ) = @_;

    $self->_playVideo( $self->{ outFileName }->GetValue );
}

sub _playVideo {
    my ( $self, $file ) = @_;

    my $vf = "drawtext=text='timestamp\: %{pts \\: hms}':fontsize=72:r=60:x=(w-tw)/2:y=h-(2*lh):fontcolor=white:box=1:boxcolor=0x00000099";

    `ffplay -i "$file" -vf "$vf" 2>&1`;
}

sub _getClapTimestamp {
    my ( $self, $file, $to ) = @_;

    my $tmp = "/tmp/$0.$$.wav";

    my $log = $self->_ff(
        "-to $to -i \"$file\" -ac 1 $tmp",
        "-nostats -i $tmp -filter_complex ebur128=peak=true -f null -"
    );

    `rm $tmp`;

    $log =~ /Peak:\s+(-?[0-9\.]+)/;

    my $peak = $1;

    for ( split /\n/, $log ) {
        next unless m/Parsed_ebur128/;
        next if m/Summary/;
        next if m/inf/;

        my @P = split /[\s\:]+/;
        my ($t, $tpk) = map { $P[$_] } 4, 22;

        return $t if $tpk == $peak;
    }
}

sub getLoudnessData {
    my ( $self, $evt ) = @_;

    my $f = $self->{ audioFile }->GetValue;
    my $s = $self->{ clapTimestampValue }->GetValue;

    $self->{ status_bar }->SetStatusText('Getting loudness data...', 0);

    my $data = $self->_getLoudnessData($f, $s);

    $self->setStatusText;

    $self->{ Settings } = {
        thresholdValue     => $data->{ measured_thresh } + 0.0,
        loudnessValue      => $data->{ measured_i } + 0.0,
        clapTimestampValue => $s,
    };

    $self->createSettings;
}

sub _getLoudnessData {
    my ( $self, $f, $s ) = @_;

    my $tmp = "/tmp/$0.$$.wav";

    my $json = $self->_ff(
        "-ss $s -i \"$f\" -ac 1 -ar 48k $tmp",
        "-i $tmp -af loudnorm=dual_mono=true:print_format=json -f null -"
    );

    `rm $tmp`;

    $json =~ /(\{[^\{\}]+\})/;

    my $data = decode_json($1);
    my $lmap = {
        offset          => $data->{ target_offset },
        measured_i      => $data->{ input_i },
        measured_lra    => $data->{ input_lra },
        measured_tp     => $data->{ input_tp },
        measured_thresh => $data->{ input_thresh },
    };

    return $lmap;
}

sub doLoadAudio {
    my ( $self ) = @_;
    $self->_LoadFile('audioFile', 'Load file', '*.*', './');
}

sub doLoadVideo {
    my ( $self ) = @_;
    $self->_LoadFile('videoFile', 'Load file', '*.*', './');
}

sub _LoadFile {
    my ($self, $field, $caption, $wildcard, $defaultDir) = @_;

    my $fileDialog = Wx::FileDialog->new(
        $self,
        $caption,
        $defaultDir,
        '',
        $wildcard,
        wxFD_OPEN
    );

    my $status = $fileDialog->ShowModal;

    my $dir  = $fileDialog->GetDirectory;
    my $file = $fileDialog->GetFilename;

    $self->{ $field }->Clear();
    $self->{ $field }->WriteText($dir . '/' . $file);

    $self->{ $field }->Clear() if $status == wxID_CANCEL;
}

sub BtnEvent {
    my ($self, $evt) = @_;

    Wx::Event::EVT_BUTTON($self, $self->{ $evt }->GetId, $self->can( $evt ));
}

1;

package ImgViewer;

use Wx qw[:everything];
use base qw(Wx::Dialog);
use strict;

sub new {
    my( $self, $parent, $title, $img ) = @_;

    $self = $self->SUPER::new(
        $parent, -1,
        $title,
        wxDefaultPosition,
        Wx::Size->new(640, 480),
        wxDEFAULT_DIALOG_STYLE,
        ''
    );

    my $sizer = Wx::BoxSizer->new(wxVERTICAL);
    my $bitmap = Wx::StaticBitmap->new($self, wxID_ANY, Wx::Bitmap->new($img, wxBITMAP_TYPE_ANY));

    $sizer->Add($bitmap, 0, 0, 0);

    $self->SetSizer($sizer);
    $self->Layout;

    return $self;
}

1;

package ACXSync;

use base qw(Wx::App);
use strict;
use warnings;

sub OnInit {
    my( $self ) = shift;

    exit 1 if fork;

    Wx::InitAllImageHandlers();

    my $frame = MainFrame->new( 'ACX Tools' );

    $frame->Show;
    $self->MainLoop;

    return 1;
}

=pod

Run app:
 $ acx_gui &
