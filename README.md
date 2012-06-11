# ShowBrake
### Rip TV shows using HandBrakeCLI and (optionally) iFlicks

#### Requirements

This script has only been tested on Mac OS Lion 10.7.4. It requires the **HandBrakeCLI** binary, available from <http://handbrake.fr/downloads2.php>. You should also install **libdvdcss**, available from <http://download.videolan.org/pub/libdvdcss/last/macosx/>.

#### Compatibility

There are some discs HandBrake just can't read; in those cases I've found [RipIt](http://thelittleappfactory.com/ripit/) does the job. It'll create a `.dvdmedia` package; just pass it to the script as a command-line argument and you're set. Most blu-rays fall into this category — I use [Pavtube Blu-ray Ripper](http://www.pavtube.com/blu-ray-ripper-mac/) to copy the entire disc to my hard drive first, but most blu-ray ripping software is OK (e.g. [MakeMKV](http://www.makemkv.com/)).

For some DVDs, disabling **libdvdnav** can get you past little glitches (and slow you down bigtime, oh well). Run ShowBrake with the `--no-dvdnav` command-line argument, and ShowBrake will pass it on to **HandBrakeCLI**.

#### Episode sequences

It's sometimes impossible to guess which titles/chapters on a disc are episodes, so ShowBrake will do its best, but you have the ultimate say. When it asks you for the episode list, you can specify titles (e.g. `1 2 3`), chapters (e.g. `1.1 1.2 1.3`) or in rare cases, ranges of chapters (e.g. `1.1-4 1.5-8 1.9-12`).

#### Being good

I wrote this script so that I could watch show I'd purchased when I travel. Please respect my work, and the work of TV producers, by not using it to violate intellectual property laws.

*- Neil*