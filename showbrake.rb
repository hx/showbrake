#!/usr/bin/ruby

require 'yaml'
require 'stringio'
require 'shellwords'

STDOUT.sync = true

class Application

  MINIMUM_EPISODE_LENGTH = 600
  
  EPISODE_DURATION_DEVIATION = 0.25

  ENCODING_DEFAULTS = {

    :common => {
      :encoder => 'x264',
      :quality => 20,
      :optimize => true,
      :audio => '1,1',
      :aencoder => 'faac,copy:ac3',
      :ab => '160,160',
      :mixdown => 'dpl2,auto',
      :arate => 'auto,auto',
      :drc => '0.0,0.0',
      :format => 'mp4',
      :'loose-anamorphic' => true,
      :markers => true
    },

    :dvd => {
      :maxWidth => 720,
      :encopts => 'cabac=0:ref=2:me=umh:bframes=0:weightp=0:8x8dct=0:trellis=0:subme=6',
    },

    :bluray => {
      :maxWidth => 1280,
      :'large-file' => true,
      :rate => 29.97,
      :pfr => true
    }
    
  }

  def self.readline valid_pattern, default = nil
    begin
      print '[ %s ] ' % default unless default.nil?
      print '> '
      ret = STDIN.gets.strip
      valid = case valid_pattern.class.object_id
        when Regexp.object_id then
          ret =~ valid_pattern
        when Range.object_id then
          valid_pattern === ret.to_i
      end
      use_default = ret == '' && !default.nil?
    end until valid or use_default
    use_default ? default : ret
  end

  def self.choose options, default = nil
    return 0 if options.length < 2
    options.each_with_index { |option, i| puts '%s) %s' % [ i + 1, option ] }
    readline( 1..options.length, default && default + 1 ).to_i - 1
  end

  def self.confirm default = true
    readline( /^(y(es)?|no?)$/i, default.nil? ? nil : default ? 'Y' : 'N' )[ 0, 1 ].upcase == 'Y'
  end

  def self.main

    if media_type = Disc.media_type( ARGV[ 0 ].to_s )

      volume = File.expand_path ARGV.shift.to_s

    else

      volumes = Disc.list_of_volumes
      abort "Could not find any DVD or Blu-ray video volumes" if volumes.length == 0

      volume = '/Volumes/' + if volumes.length > 1
        puts "Which disc would you like to rip?"
        volumes[ choose volumes ]
      else
        volumes[ 0 ]
      end

      media_type = Disc.media_type volume

    end

    show_title = Persist[ :title ]
    puts "What is the show’s name?"
    new_title = readline /.+/, show_title
    same_title_as_before = show_title == new_title
    Persist[ :title ] = show_title = new_title

    season = same_title_as_before ? Persist[ :season ] || 1 : 1
    puts "Which season?"
    new_season = ( readline 1..100, season ).to_i
    same_season_as_before = same_title_as_before && season == new_season
    Persist[ :season ] = season = new_season

    puts "Which is the first episode on this disc?"
    first_episode = ( readline 1..100, same_season_as_before ? Persist[ :episode ].to_i + 1 : 1 ).to_i

    if media_type == :dvd

      puts "Try to include foreign-language subtitles?"
      Persist[ :foreign_subs ] = foreign_subs = confirm( Persist[ :foreign_subs ] || false )

      puts "Apply motion-sensing decomb filter (for video-based sources)?"
      Persist[ :decomb ] = decomb = choose([
        'Off',
        'Automatic',
        'Upper field first (NTSC)',
        'Lower field first (PAL)'
      ], Persist[ :decomb ] || 1)

    end

    if Iflicks.installed?
      puts "Add episodes to iFlicks?"
      options = [
        'Do not add to iFlicks',
        'Add to iFlicks, but do not queue',
        'Add to iFlicks and queue immediately'
      ]
      Persist[ :iFlicks ] = Iflicks.option = choose( options, Persist[ :iFlicks ] || 2 )
    end

    disc = Disc.new volume

    disc.print_breakdown

    usable_titles = disc.titles.reject{ |title| title.duration < MINIMUM_EPISODE_LENGTH }.sort!{ |a, b| a.duration <=> b.duration }

    if usable_titles.length > 1
      normal_duration = usable_titles[ -2 ].duration
      usable_titles.reject!{ |title| ( normal_duration - title.duration ).abs > normal_duration * EPISODE_DURATION_DEVIATION }
    end

    episode_map = if usable_titles.length == 1
      title = usable_titles[ 0 ]
      if title.chapters.length > 1
        usable_chapters = title.chapters.reject{ |chapter| chapter.duration < MINIMUM_EPISODE_LENGTH }
        if usable_chapters.length > 1
          usable_chapters.map{ |chapter| '%s.%s' % [ title.index + 1, chapter.number ] }.join( ' ' )
        else
          ( title.index + 1 ).to_s
        end
      else
        ( title.index + 1 ).to_s
      end
    else
      usable_titles.sort!{ |a, b| a.index <=> b.index }
      usable_titles.map{ |title| ( title.index + 1 ).to_s }.join( ' ' )
    end

    puts "Enter the title, chapters or chapter ranges for each episode,"
    puts "separated by spaces."

    begin
      episode_map_pattern = /^[1-9]\d*(?:\.[1-9]\d*(?:-[1-9]\d*)?)?(?: [1-9]\d*(?:\.[1-9]\d*(?:-[1-9]\d*)?)?)*$/
      episodes = ( readline episode_map_pattern, episode_map ).split( ' ' ).map{ |description| Episode.new( disc, description ) }
    end while episodes.any? { |episode| !episode.valid? }

    episodes.each_with_index do |episode, index|
      filename = '%s S%02dE%02d.mp4' % [ show_title, season, first_episode + index ]
      puts 'Creating %s' % filename
      Handbrake.rip episode, filename, :foreign_subs => foreign_subs, :decomb => decomb
      Iflicks << File.expand_path( filename )
    end

    Persist[ :episode ] = first_episode + episodes.length - 1

  end

end

module AnsiEscape

  COLOUR_INDEX = {
    :black => 0,
    :red => 1,
    :green => 2,
    :yellow => 3,
    :blue => 4,
    :magenta => 5,
    :cyan => 6,
    :white => 7
  }

  STYLE_INDEX = {
    :bold => 1,
    :italic => 3,
    :underline => 4,
    :inverse => 7,
    :strikethrough => 4
  }

  def self.colour args
    return escape '0m' if args == :reset
    args.each do |key, value|
      if code = STYLE_INDEX[ key ]
        code += value ? 0 : 20
      else
        code = COLOUR_INDEX[ value ] + ( key == :foreground ? 30 : 40 )
      end
      escape code.to_s + 'm'
    end
  end

  def self.up lines = 1
    escape lines.to_s + 'A'
  end

  def self.down lines = 1
    escape lines.to_s + 'B'
  end

  def self.right cols = 1
    escape cols.to_s + 'C'
  end

  def self.left cols = 1
    escape cols.to_s + 'D'
  end

  def self.escape value
    print "\x1b[" + value
  end

end

module Media

  def duration_s
    minutes, seconds = duration.divmod 60
    hours, minutes = minutes.divmod 60
    ret = "%02dm %02ds" % [ minutes, seconds ]
    ret = "%sh %s" % [ hours, ret ] if hours > 0
    ret
  end

end

class Episode

  attr_accessor :title, :chapters, :disc

  def initialize disc, description
    @disc = disc
    match = /^(\d+)(?:\.(\d+)(?:-(\d+))?)?$/.match( description )
    @title = match[ 1 ].to_i
    @chapters = if match[ 2 ].nil?
      nil
    elsif match[ 3 ].nil?
      match[ 2 ].to_i
    else
      match[ 2 ].to_i..match[ 3 ].to_i
    end
  end

  def valid?
    return false if @title < 1 or @title > @disc.titles.length
    return true if @chapters.nil?
    title_chapter_range = 1..@disc.titles[ @title - 1 ].chapters.length
    if @chapters.respond_to? :first
      title_chapter_range === @chapters.first && title_chapter_range === @chapters.last
    else
      title_chapter_range === @chapters
    end
  end

end

class Disc

  include Media

  attr_reader :titles, :path

  def self.list_of_volumes

    ret = []

    StringIO.new( `df -l` ).each_line do |line|
      volume = line[ /\/Volumes\/(.*)/, 1 ]
      ret << volume unless volume.nil? or !media_type '/Volumes/' + volume
    end

    ret
    
  end

  def self.media_type volume

    path = File.expand_path volume

    return :dvd if File.directory? path + '/VIDEO_TS'
    return :bluray if File.directory? path + '/BDMV'

  end

  def initialize volume
    
    @path = volume
    @titles_scanned = 0
    @titles = []

    puts "Reading disc info (this can take a few minutes)..."

    title_data_class = nil

    Handbrake.exec :input => @path, :title => 0, :'min-duration' => Application::MINIMUM_EPISODE_LENGTH do |line|

      self.title_count = line[ /Disc has (\d+) title/, 1 ]
      self.titles_scanned = line[ /Scanning title (\d+) of/, 1 ]
      if line =~ /scan thread found \d+ valid title/
        AnsiEscape.down
        AnsiEscape.left @titles_scanned + 1
      elsif match = /\+ title (\d+):/.match( line )
        @titles << Title.new( match[ 1 ].to_i, @titles.length )
        title_data_class = nil
      elsif match = /\+ (chapters|(audio|subtitle) tracks):/.match( line )
        title_data_class = case match[ 1 ]
          when 'chapters' then Chapter
          when 'audio tracks' then AudioTrack
          when 'subtitle tracks'then SubtitleTrack
        end
      elsif match = /^ {4}\+ (\d+)[:,] (.*)$/.match( line )
        @titles[ -1 ].add_data title_data_class.new( match[ 1 ].to_i, match[ 2 ] )
      end

    end

  end

  def media_type
    return Disc.media_type @path
  end

  def title_count= value
    return if @title_count || value.nil?
    @title_count = value.to_i
    puts "Scanning %s title%s..." % [ @title_count, @title_count == 1 ? '' : 's' ]
    puts "[" + ' ' * @title_count + ']'
    AnsiEscape.up; AnsiEscape.right
  end

  def titles_scanned= value
    value_i = [ value.to_i, @title_count.to_i ].min
    while @titles_scanned < value_i
      @titles_scanned += 1
      print '-'
    end
  end

  def duration
    @titles.inject( 0 ) { |sum, title| sum + title.duration }
  end

  def print_breakdown
    puts ''
    puts 'Disc duration: ' + duration_s
    puts ''
    @titles.each do |title|
      puts '%s) title %s %s' % [ ( title.index + 1 ).to_s.rjust( 2 ), title.number.to_s.ljust( 5 ), title.duration_s ]
      title.chapters.each do |chapter|
        puts '  %s) chapter   %s' % [ chapter.number.to_s.rjust( 2 ), chapter.duration_s ]
      end
      puts ''
    end
  end

end

class Title

  include Media

  attr_reader :number, :chapters, :audio_tracks, :subtitle_tracks, :index

  def initialize number, index
    @number = number
    @index = index
    @chapters = []
    @audio_tracks = []
    @subtitle_tracks = []
  end

  def add_data data
    case data.class.object_id
      when Chapter.object_id then @chapters << data
      when SubtitleTrack.object_id then @subtitle_tracks << data
      when AudioTrack.object_id then @audio_tracks << data
    end
  end

  def duration
    @chapters.inject( 0 ) { |total, chapter| total + chapter.duration }
  end

end

class TitleData

  attr_reader :number, :data

  def initialize number, data
    @number = number
    @data = data
  end

end

class Chapter < TitleData

  include Media

  alias :super_init :initialize

  attr_reader :duration

  def initialize number, data
    super_init number, data
    @duration = 0
    if match = /duration (\d\d):(\d\d):(\d\d)/.match( data )
      @duration = match[ 1 ].to_i * 60 * 60 + match[ 2 ].to_i * 60 + match[ 3 ].to_i
    end
  end

end

class AudioTrack < TitleData

end

class SubtitleTrack < TitleData

end

class Handbrake

  EXECUTABLE_NAME = 'HandBrakeCLI'

  [ File.dirname( __FILE__ ), '/usr/bin', '/Applications' ].each do |dir|
    @@executable_path = File.expand_path( dir + '/' + EXECUTABLE_NAME )
    break if File.executable? @@executable_path
  end

  abort "Could not find HandBrakeCLI executable" unless File.executable? @@executable_path

  def self.exec args, display = false
    cmd = Shellwords.shellescape @@executable_path
    args.each { |key, value| cmd += " --%s %s" % [ key, value == true ? '' : Shellwords.shellescape( value.to_s ) ] if value }
    cmd += ARGV.map{ |x| ' ' + Shellwords.shellescape( x ) }.join unless ARGV.empty?
    if block_given?
      IO.popen( cmd + ' 2>&1' ).each_line { |line| yield line }
    elsif display
      AnsiEscape.colour :foreground => :green
      result = system cmd + ' 2> /dev/null'
      AnsiEscape.colour :reset
      abort 'Command failed or was aborted' unless result
    else
      IO.popen( cmd + ' 2> /dev/null' ).read
    end
  end

  def self.rip episode, output_file, options
    args = Application::ENCODING_DEFAULTS[ :common ].merge(
        Application::ENCODING_DEFAULTS[ episode.disc.media_type ]
      ).merge( {
      :input => episode.disc.path,
      :title => episode.disc.titles[ episode.title - 1 ].number,
      :output => output_file
    } )
    args.update( {
      :subtitle => 'scan',
      :'subtitle-burn' => true,
      :'native-lang' => 'eng'
    } ) if options[ :foreign_subs ]
    args[ :decomb ] = /--decomb[\s\S]+?default: ([-:\d]+:)/.match( exec :help => true )[ 1 ] + ( options[ :decomb ] - 2 ).to_s if options[ :decomb ] && options[ :decomb ] > 0
    args[ :chapters ] = if episode.chapters.respond_to? :first
      '%s-%s' % [ episode.chapters.first, episode.chapters.last ]
    else
      episode.chapters
    end if episode.chapters
    exec args, true
  end

end

class Iflicks

  COMMAND_TEMPLATE = 'osascript' + '

tell application "iFlicks"
import "%s" as iTunes compatible with%s gui with deleting
end tell

  '.strip.split( "\n" ).map{ |line| " -e '%s'" % line }.join

  def self.installed?
    File.directory? '/Applications/iFlicks.app'
  end

  def self.option= value
    @@option = value
  end

  def self.<< file
    return if @@option == 0
    system COMMAND_TEMPLATE % [ file, @@option == 2 ? 'out' : '' ]
  end

end

class Persist

  def self.write
    File.open( @@data_path, 'w' ) { |file| file.write YAML::dump @@data }
  end

  def self.[]=( key, value )
    @@data[ key ] = value
    write
  end

  def self.[]( key )
    @@data[ key ]
  end

  @@data = {}

  @@data_path = File.expand_path( __FILE__ ) + '.data'

  File.open( @@data_path, 'r' ) do |file|
    @@data = YAML::load file.read
  end if File.exists? @@data_path

end

Application.main
