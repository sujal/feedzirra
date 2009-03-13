require File.dirname(__FILE__) + '/../spec_helper'

describe Feedzirra::Feed do
  describe "#parse" do # many of these tests are redundant with the specific feed type tests, but I put them here for completeness
    context "when there's an available parser" do
      it "should parse an rdf feed" do
        feed = Feedzirra::Feed.parse(sample_rdf_feed)
        feed.title.should == "HREF Considered Harmful"
        feed.entries.first.published.to_s.should == "Tue Sep 02 19:50:07 UTC 2008"
        feed.entries.size.should == 10
      end

      it "should parse an rss feed" do
        feed = Feedzirra::Feed.parse(sample_rss_feed)
        feed.title.should == "Tender Lovemaking"
        feed.entries.first.published.to_s.should == "Thu Dec 04 17:17:49 UTC 2008"
        feed.entries.size.should == 10
      end

      it "should parse an atom feed" do
        feed = Feedzirra::Feed.parse(sample_atom_feed)
        feed.title.should == "Amazon Web Services Blog"
        feed.entries.first.published.to_s.should == "Fri Jan 16 18:21:00 UTC 2009"
        feed.entries.size.should == 10
      end

      it "should parse an feedburner atom feed" do
        feed = Feedzirra::Feed.parse(sample_feedburner_atom_feed)
        feed.title.should == "Paul Dix Explains Nothing"
        feed.entries.first.published.to_s.should == "Thu Jan 22 15:50:22 UTC 2009"
        feed.entries.size.should == 5
      end
    end

    context "when there's no available parser" do
      it "raises Feedzirra::NoParserAvailable" do
        proc {
          Feedzirra::Feed.parse("I'm an invalid feed")
        }.should raise_error(Feedzirra::NoParserAvailable)
      end
    end

    it "should parse an feedburner rss feed" do
      feed = Feedzirra::Feed.parse(sample_rss_feed_burner_feed)
      feed.title.should == "Sam Harris: Author, Philosopher, Essayist, Atheist"
      feed.entries.first.published.to_s.should == "Tue Jan 13 17:20:28 UTC 2009"
      feed.entries.size.should == 10
    end
  end

  describe "#determine_feed_parser_for_xml" do
    it "should return the Feedzirra::Atom class for an atom feed" do
      Feedzirra::Feed.determine_feed_parser_for_xml(sample_atom_feed).should == Feedzirra::Atom
    end

    it "should return the Feedzirra::AtomFeedBurner class for an atom feedburner feed" do
      Feedzirra::Feed.determine_feed_parser_for_xml(sample_feedburner_atom_feed).should == Feedzirra::AtomFeedBurner
    end

    it "should return the Feedzirra::RSS class for an rdf/rss 1.0 feed" do
      Feedzirra::Feed.determine_feed_parser_for_xml(sample_rdf_feed).should == Feedzirra::RSS
    end

    it "should return the Feedzirra::RSS class for an rss feedburner feed" do
      Feedzirra::Feed.determine_feed_parser_for_xml(sample_rss_feed_burner_feed).should == Feedzirra::RSS
    end

    it "should return the Feedzirra::RSS object for an rss 2.0 feed" do
      Feedzirra::Feed.determine_feed_parser_for_xml(sample_rss_feed).should == Feedzirra::RSS
    end
  end

  describe "when adding feed types" do
    it "should prioritize added types over the built in ones" do
      feed_text = "Atom asdf"
      Feedzirra::Atom.should be_able_to_parse(feed_text)
      new_feed_type = Class.new do
        def self.able_to_parse?(val)
          true
        end
      end
      
      new_feed_type.should be_able_to_parse(feed_text)
      Feedzirra::Feed.add_feed_class(new_feed_type)
      Feedzirra::Feed.determine_feed_parser_for_xml(feed_text).should == new_feed_type

      # this is a hack so that this doesn't break the rest of the tests
      Feedzirra::Feed.feed_classes.reject! {|o| o == new_feed_type }
    end
  end

  describe '#etag_from_header' do
    before(:each) do
      @header = "HTTP/1.0 200 OK\r\nDate: Thu, 29 Jan 2009 03:55:24 GMT\r\nServer: Apache\r\nX-FB-Host: chi-write6\r\nLast-Modified: Wed, 28 Jan 2009 04:10:32 GMT\r\nETag: ziEyTl4q9GH04BR4jgkImd0GvSE\r\nP3P: CP=\"ALL DSP COR NID CUR OUR NOR\"\r\nConnection: close\r\nContent-Type: text/xml;charset=utf-8\r\n\r\n"
    end

    it "should return the etag from the header if it exists" do
      Feedzirra::Feed.etag_from_header(@header).should == "ziEyTl4q9GH04BR4jgkImd0GvSE"
    end

    it "should return nil if there is no etag in the header" do
      Feedzirra::Feed.etag_from_header("foo").should be_nil
    end

  end

  describe '#last_modified_from_header' do
    before(:each) do
      @header = "HTTP/1.0 200 OK\r\nDate: Thu, 29 Jan 2009 03:55:24 GMT\r\nServer: Apache\r\nX-FB-Host: chi-write6\r\nLast-Modified: Wed, 28 Jan 2009 04:10:32 GMT\r\nETag: ziEyTl4q9GH04BR4jgkImd0GvSE\r\nP3P: CP=\"ALL DSP COR NID CUR OUR NOR\"\r\nConnection: close\r\nContent-Type: text/xml;charset=utf-8\r\n\r\n"
    end

    it "should return the last modified date from the header if it exists" do
      Feedzirra::Feed.last_modified_from_header(@header).should == Time.parse("Wed, 28 Jan 2009 04:10:32 GMT")
    end

    it "should return nil if there is no last modified date in the header" do
      Feedzirra::Feed.last_modified_from_header("foo").should be_nil
    end
  end

  describe "fetching feeds" do
    before(:each) do
      @paul_feed = { :xml => load_sample("PaulDixExplainsNothing.xml"), :url => "http://feeds.feedburner.com/PaulDixExplainsNothing" }
      @trotter_feed = { :xml => load_sample("TrotterCashionHome.xml"), :url => "http://feeds2.feedburner.com/trottercashion" }
    end

    describe "#fetch_raw" do
      before(:each) do
        @cmock = stub('cmock', :header_str => '', :body_str => @paul_feed[:xml] )
        @multi = stub('curl_multi', :add => true, :perform => true)
        @curl_easy = stub('curl_easy')
        @curl = stub('curl', :headers => {}, :follow_location= => true, :on_failure => true)
        @curl.stub!(:on_success).and_yield(@cmock)
        
        Curl::Multi.stub!(:new).and_return(@multi)
        Curl::Easy.stub!(:new).and_yield(@curl).and_return(@curl_easy)
      end

      it "should set user agent if it's passed as an option" do
        Feedzirra::Feed.fetch_raw(@paul_feed[:url], :user_agent => 'Custom Useragent')
        @curl.headers['User-Agent'].should == 'Custom Useragent'
      end

      it "should set user agent to default if it's not passed as an option" do
        Feedzirra::Feed.fetch_raw(@paul_feed[:url])
        @curl.headers['User-Agent'].should == Feedzirra::Feed::USER_AGENT
      end
      
      it "should set if modified since as an option if passed" do
        Feedzirra::Feed.fetch_raw(@paul_feed[:url], :if_modified_since => Time.parse("Wed, 28 Jan 2009 04:10:32 GMT"))
        @curl.headers["If-Modified-Since"].should == 'Wed, 28 Jan 2009 04:10:32 GMT'
      end

      it "should set if none match as an option if passed"
      
      it 'should set userpwd for http basic authentication if :http_authentication is passed' do
        @curl.should_receive(:userpwd=).with('username:password')
        Feedzirra::Feed.fetch_raw(@paul_feed[:url], :http_authentication => ['username', 'password'])
      end

      it 'should set accepted encodings' do
        Feedzirra::Feed.fetch_raw(@paul_feed[:url])
        @curl.headers["Accept-encoding"].should == 'gzip, deflate'
      end

      it "should return raw xml" do
        Feedzirra::Feed.fetch_raw(@paul_feed[:url]).should =~ /^#{Regexp.escape('<?xml version="1.0" encoding="UTF-8"?>')}/
      end

      it "should take multiple feed urls and return a hash of urls and response xml" do
        multi = stub('curl_multi', :add => true, :perform => true)
        Curl::Multi.stub!(:new).and_return(multi)
        
        paul_response = stub('paul_response', :header_str => '', :body_str => @paul_feed[:xml] )
        trotter_response = stub('trotter_response', :header_str => '', :body_str => @trotter_feed[:xml] )

        paul_curl = stub('paul_curl', :headers => {}, :follow_location= => true, :on_failure => true)
        paul_curl.stub!(:on_success).and_yield(paul_response)

        trotter_curl = stub('trotter_curl', :headers => {}, :follow_location= => true, :on_failure => true)
        trotter_curl.stub!(:on_success).and_yield(trotter_response)
        
        Curl::Easy.should_receive(:new).with(@paul_feed[:url]).ordered.and_yield(paul_curl)
        Curl::Easy.should_receive(:new).with(@trotter_feed[:url]).ordered.and_yield(trotter_curl)
        
        results = Feedzirra::Feed.fetch_raw([@paul_feed[:url], @trotter_feed[:url]])
        results.keys.should include(@paul_feed[:url])
        results.keys.should include(@trotter_feed[:url])
        results[@paul_feed[:url]].should =~ /Paul Dix/
        results[@trotter_feed[:url]].should =~ /Trotter Cashion/
      end

      it "should always return a hash when passed an array" do
        results = Feedzirra::Feed.fetch_raw([@paul_feed[:url]])
        results.class.should == Hash
      end
    end

    describe "#add_url_to_multi" do
      before(:each) do
        @multi_curl = Curl::Multi.new(@paul_feed[:url])
        @url_queue = []
        @responses = {}
      end

      it "should set user agent if it's passed as an option" do
        @url_queue << @paul_feed[:url]
        url = Feedzirra::Feed.add_url_to_multi(@multi_curl, @paul_feed[:url], @url_queue, @responses, {})
        puts url.inspect
      end
      
      it "should set user agent to default if it's not passed as an option"
      it "should set if modified since as an option if passed"
      it 'should set follow location to true'
      it 'should set userpwd for http basic authentication if :http_authentication is passed'
      it 'should set accepted encodings'
      it "should set if_none_match as an option if passed"
      
      describe 'on success' do
        it 'should decode the response body'
        it 'should determine the xml parser class'
        
        describe 'when a compatible xml parser class is found' do
          it 'should call proc if :on_success option is passed'
        end

        describe 'when no compatible xml parser class is found' do
          it 'should do something other than puts'
        end
      end

      describe 'on failure' do
        it 'should call proc if :on_failure option is passed'
        it 'should return the http code in the responses'
      end
    end

    describe "#add_feed_to_multi" do
      it "should set user agent if it's passed as an option"
      it "should set user agent to default if it's not passed as an option"
      it "should set if modified since as an option if passed"
      it 'should set follow location to true'
      it 'should set userpwd for http basic authentication if :http_authentication is passed'
      it 'should set accepted encodings'
      it "should set if_none_match as an option if passed"

      describe 'on success' do
        it 'if :on_success option is called, should call proc'
      end

      describe 'on failure' do
        it 'if :on_failure option is called, should call proc'
      end
    end

    describe "#fetch_and_parse" do
      it 'should initiate the fetching and parsing using multicurl'
      it "should pass any request options through to add_url_to_multi"
      it 'should slice the feeds into groups of thirty for processing'
      it "should return a feed object if a single feed is passed in"
      it "should return an return an array of feed objects if multiple feeds are passed in"
    end

    describe "#decode_content" do
      it 'should decode the response body using gzip if the Content-Encoding: is gzip'
      it 'should deflate the response body using inflate if the Content-Encoding: is deflate'
      it 'should return the response body if it is not encoded'
    end

    describe "#update" do
      it 'should initiate the updating using multicurl'
      it "should pass any request options through to add_feed_to_multi"
      it 'should slice the feeds into groups of thirty for processing'
      it "should return a feed object if a single feed is passed in"
      it "should return an return an array of feed objects if multiple feeds are passed in"
    end
  end
end