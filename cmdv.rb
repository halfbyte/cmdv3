#!/usr/bin/env ruby
require 'rubygems'
require 'camping'
require 'camping/session'
require 'basic_authentication'
require 'builder'
require 'yaml'
Camping.goes :Cmdv

module Cmdv
  include Camping::BasicAuth
  include Camping::Session
  
  def authenticate(u, p)
    p == Cmdv.config[:password]
  end
  module_function :authenticate
  
end

module Cmdv::Models
  class Paste < Base
    def short_body
      body.split(/[\n\r]{1,2}/)[0..5].join("\n")
    end
    def lines
      body.split(/[\n\r]{1,2}/).size
    end
  end
  
  class CreatePaste < V 0.1
    def self.up
      create_table :cmdv_pastes, :force => true do |t|
        t.text :body, :null => false
        t.string :user, :null => false
        t.timestamps
      end
    end
    def self.down
      drop_table :cmdv_pastes
    end
  end
  class PasteHasLang < V 0.2
    def self.up
      add_column :cmdv_pastes, :type, :string
    end
    def self.down
      remove_column :cmdv_pastes, :type
    end
  end
  class PasteHasType < V 0.4
    def self.up
      add_column :cmdv_pastes, :lang, :string
      remove_column :cmdv_pastes, :type
    end
    def self.down
      remove_column :cmdv_pastes, :lang      
    end
  end
end

module Cmdv::Controllers
  class Index < R("/")
    def get
      @pastes = Paste.find(:all, :order => 'created_at DESC')
      render :list
    end
  end
  class Feed < R '/feed'
    def get
      @headers['Content-Type'] = 'application/rss+xml'
      @pastes = Paste.find(:all, :order => 'created_at DESC', :limit => 10)
      render :feed
    end
  end
  class Show < R '/paste/(\d+)'
    def get(id)
      @paste = Paste.find(id)
      render :show
    end
  end
  
  class Delete < R '/delete(\d+)'
    def post(id)
      @paste = Paste.find(id)
      @paste.destroy
      redirect R(Index)
    end
  end
  
  class New < R '/new'
    def get
      @paste = Paste.new
      render :new
    end
    
    def post
      @paste = Paste.new(@input.paste)
      @paste.user = @username ||'unauthorized'
      if @paste.save
        redirect R(Index)
      else
        render :new
      end
    end
  end
  
  class Static < R '/static/(.+)'
    MIME_TYPES = {'.css' => 'text/css', '.js' => 'text/javascript', '.jpg' => 'image/jpeg', '.png' => 'image/png', '.gif' => 'image/gif'}
    PATH = File.expand_path(File.dirname(__FILE__))
    def get(path)
      @headers['Content-Type'] = MIME_TYPES[path[/\.\w+$/, 0]] || "text/plain"
      unless path.include? ".." # prevent directory traversal attacks
        @headers['X-Sendfile'] = "#{PATH}/static/#{path}"
      else
        @status = "403"
        "403 - Invalid path"
      end
    end
  end

  class Edit < R '/edit/(\d+)'
    def get(id)
      @paste = Paste.find(id)
      render :edit
    end
    def post(id)
      @paste = Paste.find(id)
      if @paste.update_attributes(@input.paste)
        redirect R(Index)
      else
        render :edit
      end
    end
    
  end
end

module Cmdv::Views
  def layout
    if @headers['Content-Type'] == 'application/rss+xml'
      self << yield 
    else
      
      html do
        head do
          title "cmdv v3 - hacker's camp"
          link :type => 'text/css', :href => R(Static, 'Styles/SyntaxHighlighter.css'), :rel => 'stylesheet'
          link :type => 'text/css', :href => R(Static, 'Styles/style.css'), :rel => 'stylesheet'
          link :type => 'application/rss+xml', :href => R(Feed), :rel => 'alternate'
        end
        body do
          div.header! do
            h1 do
              a :href => R(Index) do
                "CMD-v - hacker's camp"
              end
            end
          end
          div.content! do
            self << yield
          end
          div.footer! do
            p "cmdv v3 - jan.krutisch.de - camping ftw! (hello #{@username})"
          end
          %w(shCore shBrushRuby shBrushJScript shBrushSql shBrushCss).each do |s|
            script :type => 'text/javascript',
              :src => R(Static, "Scripts/#{s}.js")
          end
          script :type => 'text/javascript' do
            self << "dp.SyntaxHighlighter.ClipboardSwf = '#{self / R(Static, 'Scripts/clipboard.swf')}';"
            self << "dp.SyntaxHighlighter.HighlightAll('code');"
          end
        end
      end
    end
  end
  
  def list
    ul.pastes do
      @pastes.each do |paste|
        li.paste do
          h2 do 
            a :href => R(Show, paste.id) do
              self << "Posted at #{paste.created_at.to_s :short} by #{paste.user}"
            end
            span.more "(#{paste.lines} lines)"
          end
          pre.code do
            self << paste.short_body
          end
        end
      end
    end
    p do
      a :href => R(New) do
        img :src => R(Static, 'Images/new.png'), :alt => 'New', :title => 'New Paste'
      end
    end
  end
  
  def show
    h2 do
      self << "Paste from "
      self << @paste.user
      self << "(#{paste.created_at.to_s :short})"
    end
    form :action => R(Delete, @paste.id), :method => 'POST' do
      a :href => R(Edit, @paste.id) do
        img :src => R(Static, 'Images/edit.png'), :alt => 'Edit', :title => 'Edit this Paste'
      end
      input :type => 'image', :src => R(Static, 'Images/delete.png'), :alt => 'Delete', :title => 'Delete this Paste', :onclick => 'return confirm("Really delete this Paste?")'
    end
    textarea :class => paste.lang, :name => 'code' do
      paste.body
    end
  end
  
  def new
    h2 "New Paste"
    errors_for(@paste)
    form :action => R(New), :method => 'POST' do
      _form
      p do
        input :type => "submit", :value => "Create"
        self << " or "
        a "Cancel", :href => R(Index)
      end
    end
  end
  
  def edit
    h2 "Edit Paste"
    errors_for(@paste)
    form :action => R(Edit, @paste.id), :method => 'POST' do
      _form
      p do
        input :type => "submit", :value => "Save"
        self << " or "
        a "Cancel", :href => R(Index)
      end
    end
  end
    
  def _form
    p do
      select :size => 1, :name => 'paste[lang]', :id => 'paste_lang' do
        %w(ruby sql css javascript).each do |lang|
          option :value => lang do
            self << lang
          end
        end
      end
    end
    p do
      textarea @paste.body, :name => 'paste[body]',
        :rows => 40,
        :cols => 80,
        :id => 'paste_body'
    end
  end
  
  def feed
    xml = Builder::XmlMarkup.new(:indent => 2)
    xml.instruct! :xml, :version=>"1.0"
    xml.rss(:version=>"2.0"){
      xml.channel{
        xml.title('Pastepaste')
        xml.link("http#{URL(Index)}")
        xml.description("hackers delight")
        xml.language('en-us')

        for paste in @pastes
          xml.item do
            xml.title("Paste from #{paste.user}")
            xml.category()
            xml.description do
              xml.cdata!(paste.body)
            end
            xml.pubDate(paste.created_at.strftime("%a, %d %b %Y %H:%M:%S %z"))
            xml.link("http#{URL(Show, paste.id)}")
            xml.link("http#{URL(Show, paste.id)}")
          end
        end
      }
    }
  end
end

def Cmdv.config
  @@config
end

def Cmdv.load_config
  config_file_name = File.join(File.dirname(File.expand_path(__FILE__)), 'config.yml')
  if File.exists?(config_file_name)
    @@config = YAML.load_file(config_file_name)
  else
    @@config = {:password => 'foobar'}
  end
end
def Cmdv.create
  Cmdv.load_config
  Camping::Models::Session.create_schema
  Cmdv::Models.create_schema
end
