require File.expand_path('app.rb', Dir.pwd)
out=[]; p=NotificationPipeline.new(out)
raise 'empty flush count' unless p.flush == 0
p.publish(actor: 'Mina', message: 'One'); p.publish(actor: 'Mina', message: 'Two')
raise 'flush count should count delivered actors' unless p.flush == 1
raise 'repeat flush should be empty' unless p.flush == 0
raise 'message output changed' unless out == ['Mina: One; Two']
