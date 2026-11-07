# frozen_string_literal: true

require "pathname"
workspace = Pathname.new(ARGV.fetch(0) { abort "usage: ruby campfire_feature_followup.rb WORKSPACE" }).expand_path
abort "Campfire workspace not found: #{workspace}" unless workspace.directory?
Dir.chdir(workspace)
$LOAD_PATH.unshift(File.join(workspace, "test"))
require "test_helper"

class HiddenRoomTopicAuthorizationFollowupTest < ActionDispatch::IntegrationTest
  test "room creator can edit topic and another member cannot" do
    sign_in :jz
    post rooms_opens_url, params: {room: {name: "Creator room"}}
    room = Room.order(:id).last
    room.memberships.grant_to(users(:kevin))

    put rooms_open_url(room), params: {room: {topic: "Creator topic"}}
    assert_redirected_to room_url(room)
    assert_equal "Creator topic", room.reload.topic

    sign_in :kevin
    put rooms_open_url(room), params: {room: {topic: "Changed by member"}}
    assert_response :forbidden
    assert_equal "Creator topic", room.reload.topic
    assert_equal "Creator room", room.reload.name
  end
end
