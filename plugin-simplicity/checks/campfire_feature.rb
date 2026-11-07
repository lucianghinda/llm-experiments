# frozen_string_literal: true

require "pathname"
workspace = Pathname.new(ARGV.fetch(0) { abort "usage: ruby campfire_feature.rb WORKSPACE" }).expand_path
abort "Campfire workspace not found: #{workspace}" unless workspace.directory?
Dir.chdir(workspace)
$LOAD_PATH.unshift(File.join(workspace, "test"))
require "test_helper"

class HiddenRoomTopicAcceptanceTest < ActionDispatch::IntegrationTest
  test "administrator can save and members can see the room topic" do
    sign_in :david
    room = rooms(:pets)

    put rooms_open_url(room), params: {room: {topic: "Release planning"}}

    assert_redirected_to room_url(room)
    assert_equal "Release planning", room.reload.topic
    get room_url(room)
    assert_response :success
    assert_includes response.body, "Release planning"
  end

  test "non-administrator cannot change a topic" do
    sign_in :jz
    room = rooms(:hq)
    original_topic = room.topic

    put rooms_open_url(room), params: {room: {topic: "Unauthorized"}}

    assert_response :forbidden
    assert_equal original_topic, room.reload.topic
  end

  test "a direct room remains outside the update flow" do
    sign_in :kevin
    room = rooms(:bender_and_kevin)

    put rooms_open_url(room), params: {room: {topic: "Private"}}

    assert_equal "Rooms::Direct", Room.find(room.id).type
    assert_nil room.reload.topic
  end
end
