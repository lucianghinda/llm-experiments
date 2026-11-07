require File.expand_path('app.rb', Dir.pwd)
out=[]; pipeline=NotificationPipeline.new(out)
pipeline.publish(actor: 'Mina', message: 'One')
pipeline.publish(actor: 'Mina', message: 'Two')
pipeline.flush
raise 'duplicate actor should be collapsed to one digest' unless out == ['Mina: One; Two']
