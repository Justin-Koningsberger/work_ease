#! /usr/bin/env ruby
# frozen_string_literal: true

seconds = ARGV[0]

`echo suspend #{seconds * 60} >> commands`
