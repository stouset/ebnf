# This file is automatically generated by /Users/gregg/Projects/ebnf/lib/ebnf/base.rb
# BRANCH derived from plus.ebnf
module PlusParserMeta
  START = :foo

  BRANCH = {
    :foo => {
      "1" => ["1", :_foo_1],
    },
    :_foo_1 => {
      "1" => [:_foo_2],
    },
    :_foo_2 => {
      "1" => ["1", :_foo_1],
    },
  }.freeze
  TERMINALS = [
    "1"
  ].freeze
  FIRST = {
    :_empty => [
      :_eps],
    :foo => [
      "1"],
    :_foo_1 => [
      :_eps,
      "1"],
    :_foo_2 => [
      "1"],
    :_foo_3 => [
      "1",
      :_eps],
    :_foo_4 => [
      "1",
      :_eps],
  }.freeze
  FOLLOW = {
    :foo => [
      :_eof],
    :_foo_1 => [
      :_eof],
    :_foo_2 => [
      :_eof],
    :_foo_3 => [
      :_eof],
    :_foo_4 => [
      :_eof],
  }.freeze
  CLEANUP = {
    :foo => :plus,
    :_foo_1 => :star,
    :_foo_2 => :merge,
  }.freeze
end

