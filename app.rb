require 'base64'
require 'rbnacl'
require 'sinatra/base'
require 'grape'
require 'data_mapper'
require 'dm-tags'
require 'geokit'
require 'dm-geokit'
require 'dm-sqlite-adapter'

if ENV["RACK_ENV"] == "development"
  DataMapper.setup :default, 'sqlite::memory:'
elsif ENV["RACK_ENV"] == "production"
  DataMapper.setup(:default, 'postgres://user:password@hostname/database')
end

class Array
  def to_d(d=6)
    self.map{|n|BigDecimal(n, 9.floor(d))}
  end
  def to_f
    self.map(&:to_f)
  end
end

class Hash
  def compact
    self.delete_if{|k,v| v==nil||v==0||v==""}
  end
end

module Coordinates
  def self.included(includer)
    includer.class_eval do
      property :latitude, Float, :index => :coordinates
      property :longitude, Float, :index => :coordinates
    end
  end
end

class User
  include DataMapper::Resource
  include DataMapper::GeoKit
  has_geographic_location :location
  property :id, Serial, required: true
  property :name, String, required: true
  property :email, String, required: true
  property :hashed_password, String, required: true
  property :salt, String, required: true

  def password=(password)
    self.salt = RbNaCl::Random.random_bytes(32)
    self.hashed_password = User.hash_password(password, self.salt)
  end

  def self.authenticate(name, password)
    user = User.first(name:name)
    if RbNaCl::Util.verify32(user.hashed_password, User.hash_password(password, user.salt))
      return user
    else
      return {messsage: "access denied"}
    end
  end

  has n, :photos
  property :pokes, Integer
  has_tags_on :interests
  has_tags_on :distastes

  def total_pokes
    self.pokes + self.photos.inject{|pokes, photo| pokes + photo.pokes}
  end

  private
  def self.hash_password(password, salt)
    RbNaCl::Hash.blake2b([password, salt].join, digest_size: 32)
  end
end

class Photo
  include DataMapper::Resource
  property :id, Serial
  belongs_to :user
  property :pokes, Integer
  PATH = "./public/images/"

  def image
    Pathname.new("#{PATH}#{self.path}").open do |file|
      return Base64.strict_encode64(file.read)
    end
  end

  def image=(string, filename)
    decoded_string = Base64.decode64 string
    self.path = self.path||filename
    File.open("#{PATH}#{self.path}", "w+") do |file|
      file.write(string)
    end
  end
end

DataMapper.finalize.auto_migrate!

class Web < Sinatra::Base
  get '/' do
    puts "Hello world."
    binding.pry
  end
end

class API < Grape::API
  format :json
  namespace :api do
    resource :users do
      desc 'look for a user around the coordinates'
      params do
        requires :latitude, type: Float, desc: "the latitude of the query"
        requires :longitude, type: Float, desc: "the longitude of the query"
      end
      get :/ do
        {message: "This is the base users route"}
      end

      desc 'create a user'
      params do
        requires :email, type: String, desc: "The new user's email"
        requires :password, type: String, desc: "This user's password"
        requires :latitude, type: Float, desc: "Users latitude"
        requires :longitude, type: Float, desc: "Users longitude"
      end
      post :id do
        User.create params
      end

      desc 'get a user by their id'
      params do
        requires :viewer, type: Integer, desc: "The observing user's id"
      end
      get :id do
        User.get params[:id]
      end

      put :id do
        User.update params[:id]
      end

      delete :id do
        User.get(params[:id]).sleep
      end

      put '/purchase' do
        User.get(params[:id]).purchase
      end
    end
  end
end
