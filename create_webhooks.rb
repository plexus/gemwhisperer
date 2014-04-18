require 'rubygems'
require 'gems'

def create_hooks(target)
  Gems.gems.each do |gem|
    Gems.add_web_hook gem['name'], target
  end
end

def remove_all_hooks
  Gems.web_hooks.each do |hook|
    name, targets = *hook
    targets.each do |target|
      Gems.remove_web_hook name == 'all gems' ? '*' : name, target['url']
    end
  end
end

create_hooks 'http://plexus-gemwhisperer.herokuapp.com/hook'

p Gems.web_hooks
