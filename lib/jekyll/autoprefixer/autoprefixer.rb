# Frozen-string-literal: true
# Encoding: utf-8

require 'autoprefixer-rails'

module Jekyll
  module Autoprefixer
    class Autoprefixer
      attr_reader :site, :batch

      def initialize(site)
        @site = site
        @batch = Array.new
      end

      def process
        options = @site.config['autoprefixer'] || {}

        if options['only_production'] && Jekyll.env != "production"
          Jekyll.logger 'Autoprefixer:', "Disabled: only_production is true but environment is #{Jekyll.env}"
          return
        end

        write_sourcemaps =
          case options['sourcemaps']
          when 'never', false then false
          when 'always', true then true
          when 'existing', nil then :transform_existing_only # Default value
          when 'production' then Jekyll.env == 'production'
          when 'development' then Jekyll.env == 'development'
          else
            Jekyll.logger.warn("Ignoring unknown value '#{options['sourcemaps']}' for autoprefixer.sourcemaps. Disabling source map generation instead.")
            false
          end

        Jekyll.logger.debug 'Autoprefixer:', 'Sourcemaps are disabled' unless write_sourcemaps

        # Process all files that were regenerated during this Jekyll build
        @batch.each do |item|
          next unless process_file?(item, options)
          path = item.destination(@site.dest)
          process_file(path, options, write_sourcemaps)
        end

        @batch.clear
      end

      private

      def process_file?(item, options)
        return true if item.data['process_with_autoprefixer'] == true
        return false if options['process_static_files'] == false && item.is_a?(Jekyll::StaticFile)
        return false if item.data['process_with_autoprefixer'] == false
        return true
      end

      def process_file(path, options, write_sourcemaps)
        Jekyll.logger.debug 'Autoprefixer:', "Transforming CSS: #{path}"

        filename = File.basename(path)
        map_path = "#{path}.map"

        begin
          file = File.open(path, 'r+')
          css = file.read

          if write_sourcemaps && File.exist?(map_path)
            Jekyll.logger.debug 'Autoprefixer:', "Transforming map: #{map_path}"

            map_file = File.open(map_path, 'r+')
            map_options = { 'prev' => map_file.read, 'inline' => false }
            map_expected = true

          elsif write_sourcemaps && write_sourcemaps != :transform_existing_only
            Jekyll.logger.debug 'Autoprefixer:', "Creating new map: #{map_path}"

            map_file = File.open(map_path, 'w+')
            map_options = { 'inline' => false }
            map_expected = true

          else
            # No sourcemaps should be written
            map_file = nil
            map_options = nil
            map_expected = false
          end

          file_options = options
            .merge({ 'map' => map_options, 'from' => filename, 'to' => filename })
            .transform_keys { |key| key.to_sym }

          result = AutoprefixerRails.process(css, file_options)
          file.truncate(0)
          file.rewind
          file.write(result)

          if result.map && map_file
            map_file.truncate(0)
            map_file.rewind
            map_file.write(result.map)
          elsif map_expected
            Jekyll.logger.error 'Autoprefixer Error:', "Failed to create sourcemap for #{filename} found at path #{path}"
          end
        ensure
          file&.close
          map_file&.close
        end
      end
    end
  end
end
