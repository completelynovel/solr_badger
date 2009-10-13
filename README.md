# SolrBadger

SolrBadger gives you useful tools to keep your database synchronized with Solr.

It has been used with Solr 1.4 (not released yet) since a year now, and been thought to be extremely flexible.

## Requirements

### Gem

    sudo gem install solr-ruby
    
## Install

    script/plugin install git@github.com:completelynovel/solr_badger.git
    or
    git checkout git@github.com:completelynovel/solr_badger.git vendor/plugins/solr_badger/

## Example

Let's say we want to keep synchronized a table called Books with our Solr instance.

The following methods returns data (it can be fields from the current model or associations...) :
- title (string)
- isbn (string)
- blurb (text)
- authors (array of names)
- classifications (array of classification names)
- popularity (integer)
- fiction (boolean)

    index_on_solr :text => :full_data_to_index, :title_s => :title, :isbn_s => :isbn,
                  :classifications_sm => :classifications, :authors_sm => :authors,                
                  :update_on_change => [:title, :isbn, :blurb, :popularity, :content_updated_at]
                  :core => :books,
                  :facet_query => ["fiction_b:true", "fiction_b:false"],
                  :facet_fields => [{ :field => :classifications_sm }, { :field => :authors_sm, :limit => 10 }]
    
    def full_data_to_index
      "#{self.title} #{self.blurb} #{self.isbn}"
    end
