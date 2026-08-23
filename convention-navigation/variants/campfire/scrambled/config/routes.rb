# Routes are split across config/routing/. The order below is significant:
# routes are matched in the order they are drawn, so the parts load in a fixed
# sequence rather than whatever the filesystem returns.
Rails.application.routes.draw do
  %w[ entry accounts people spaces posts support ].each do |part|
    part_path = Rails.root.join("config/routing/#{part}.rb")
    instance_eval(part_path.read, part_path.to_s)
  end
end
