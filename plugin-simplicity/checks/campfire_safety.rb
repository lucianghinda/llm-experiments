# frozen_string_literal: true

require "pathname"
workspace = Pathname.new(ARGV.fetch(0) { abort "usage: ruby campfire_safety.rb WORKSPACE" }).expand_path
abort "Campfire workspace not found: #{workspace}" unless workspace.directory?
Dir.chdir(workspace)
$LOAD_PATH.unshift(File.join(workspace, "test"))
require "test_helper"

class HiddenBotCredentialScopeAcceptanceTest < ActionDispatch::IntegrationTest
  test "regular user cannot use an empty bot token to post as themselves" do
    user = users(:kevin)
    bot_key = "#{user.id}-"

    assert_no_difference -> { Message.count } do
      post room_bot_messages_url(rooms(:bender_and_kevin), bot_key), params: "Unauthorized"
    end

    assert_response :redirect
  end

  test "regular user cannot use a bot key to edit their message" do
    message = messages(:fourth)
    bot_key = "#{users(:jz).id}-"
    original_body = message.plain_text_body

    patch room_bot_message_url(message.room, bot_key, message), params: +"Unauthorized edit"

    assert_response :redirect
    assert_equal original_body, message.reload.plain_text_body
  end

  test "a valid bot credential still creates and updates a bot message" do
    room = rooms(:watercooler)
    bot_key = users(:bender).bot_key

    assert_difference -> { Message.count }, 1 do
      post room_bot_messages_url(room, bot_key), params: +"Authorized bot message"
    end

    message = Message.last
    assert_response :created
    assert_equal users(:bender), message.creator

    patch room_bot_message_url(room, bot_key, message), params: +"Updated by authorized bot"

    assert_response :ok
    assert_equal "Updated by authorized bot", message.reload.plain_text_body
  end
end
