#! /usr/bin/env ruby

seconds = ARGV[0]

`echo suspend #{seconds * 60} >> commands`
