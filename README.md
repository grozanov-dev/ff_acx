# ff_acx
ffmpeg based script that sync separate recorded audio and video and makeup audio to meet ACX.

Version 3.0

Usage:

    ./ff_sync -v video -a audio -o output -s silence_sec

Example:

    ./ff_sync -v vid_01.mp4 -a aud_01.wav -o test.mp4 -s 6

Params:

    -v -- video file
    -a -- audio file
    -o -- output file
    -s -- silence in seconds

Config structure:
# ff_conf.json
```json
{
    "video" : {                         // Video params
        "bitrate"   : "5M",             // Video bitrate 5M is good for 1080p on Youtube
        "codec"     : "libx265",        // Video codec
        "framerate" : "30"              // Framerate
    },
    "audio" : {
        "lra"     : [ -32.0, -20.0 ],   // Noise gate and Compressor thresholds (see section 'Instructions below')
        "codec"   : "aac",              // Audio codec
        "bitrate" : "128k",             // Audio bitate
        "filters" : {                   // Audio filters - some pretty voice equalisation for example
                                        // "filter_type" : [
                                        //      { "filter_param" : "param_value" },
                                        //      ...
                                        // ]
                                        // For more info see <https://ffmpeg.org/ffmpeg-filters.html>
            "highpass"  : [ { "f" : 60    } ],
            "lowpass"   : [ { "f" : 12500 } ],
            "equalizer" : [
                { "f" : 80,   "t" : "q", "w" : 2.0, "g" :  2.0 },
                { "f" : 240,  "t" : "q", "w" : 6.0, "g" : -3.0 }
            ]
        }
    }
}
```
Instructions:

    - Start recording audio with your recorder.
    - Start recording video with your camera (with camera mic on).
    - Wait 2-3 secs in silence and make a hand clap.
    - Wait another 2-3 secs and start recording.
    - Run ff_stat script on audio:

    $ ./ff_stat audio.wav

    Input Integrated:    -20.7 LUFS
    ...
    Input Threshold:     -32.1 LUFS

    * edit ff_conf.json and add corresponding 'Input Integrated' and 'Input Thershold' values to audio.lra section:
    ...
        "audio" : {
            ...
            "lra" : [ -32, -20 ],
            ...
        }
    ...

    - Check the silence length in video stream:
        ! The silence in video before start of content cannot be longer than the silence before clap in audio.
        ! Alson clap in audio can not appear before clap in video (just start record audio before video).

    v Ok:
               /----- 5 sec -----\/- content -\
    video.mp4: ---------|---------|||||||||||||
                        ^ clap in video
    audio.wav: -------------|---------|||||||||||||
                            ^ clap in audio

    x Not Ok:
               /----- 5 sec -----\
    video.mp4: ---------|---------|||||||||||
                        ^ clap in video
    audio.wav: --------------------|---------|||||||||||
                                   ^ clap in audio

    x Not Ok:
               /----- 5 sec -----\
    video.mp4: ---------|---------|||||||||||
                        ^ clap in video
    audio.wav: -----|---------|||||||||||
                    ^ clap in audio

    $ ./ff_sync -v video.mp4 -a audio.wav -o podcast.mp4 -s 5

    * Enjoy!
