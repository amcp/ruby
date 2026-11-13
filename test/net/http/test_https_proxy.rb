# frozen_string_literal: false
begin
  require 'net/https'
rescue LoadError
end
require 'test/unit'

return unless defined?(OpenSSL::SSL)

class HTTPSProxyTest < Test::Unit::TestCase
  def test_https_proxy_authentication
    TCPServer.open("127.0.0.1", 0) {|serv|
      _, port, _, _ = serv.addr
      client_thread = Thread.new {
        proxy = Net::HTTP.Proxy("127.0.0.1", port, 'user', 'password')
        http = proxy.new("foo.example.org", 8000)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        begin
          http.start
        rescue EOFError
        end
      }
      server_thread = Thread.new {
        sock = serv.accept
        begin
          proxy_request = sock.gets("\r\n\r\n")
          assert_equal(
            "CONNECT foo.example.org:8000 HTTP/1.1\r\n" +
            "Host: foo.example.org:8000\r\n" +
            "Proxy-Authorization: Basic dXNlcjpwYXNzd29yZA==\r\n" +
            "\r\n",
            proxy_request,
            "[ruby-dev:25673]")
        ensure
          sock.close
        end
      }
      assert_join_threads([client_thread, server_thread])
    }
  end


  def test_https_proxy_rejects_crlf_in_address
    TCPServer.open("127.0.0.1", 0) {|serv|
      _, port, _, _ = serv.addr
      client_thread = Thread.new {
        proxy = Net::HTTP.Proxy("127.0.0.1", port)
        http = proxy.new("foo.example.org\r\nX-Injected: 1\r\nbar.example.org", 8000)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        assert_raise(ArgumentError) { http.start }
      }
      server_thread = Thread.new {
        sock = serv.accept
        sock.close
      }
      assert_join_threads([client_thread, server_thread])
    }
  end

  def read_fixture(key)
    File.read(File.expand_path("../fixtures/#{key}", __dir__))
  end

  def test_https_proxy_ssl_connection
    TCPServer.open("127.0.0.1", 0) {|tcpserver|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.key = OpenSSL::PKey.read(read_fixture("server.key"))
      ctx.cert = OpenSSL::X509::Certificate.new(read_fixture("server.crt"))
      serv = OpenSSL::SSL::SSLServer.new(tcpserver, ctx)

      _, port, _, _ = serv.addr
      received = +""
      client_thread = Thread.new {
        proxy = Net::HTTP.Proxy("127.0.0.1", port, 'user', 'password', true)
        http = proxy.new("foo.example.org", 8000)
        http.use_ssl = true
        # Origin verification must not be what authenticates the proxy.
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        http.open_timeout = 5
        assert_raise(OpenSSL::SSL::SSLError) { http.start }
      }
      server_thread = Thread.new {
        sock = nil
        begin
          unless tcpserver.wait_readable(5)
            flunk "timed out waiting for the proxy connection"
          end
          sock = serv.accept
          loop { received << sock.readpartial(4096) }
        rescue EOFError, OpenSSL::SSL::SSLError
        ensure
          sock.close if sock && !sock.closed?
        end
      }
      assert_join_threads([client_thread, server_thread])
      assert_not_match(/Proxy-Authorization/, received)
      assert_not_match(/CONNECT /, received)
    }
  end

  def test_https_proxy_ssl_connection_with_trusted_certificate
    ca_key = OpenSSL::PKey::EC.generate("prime256v1")
    ca_name = OpenSSL::X509::Name.parse("/CN=Proxy Test CA")
    ca_cert = OpenSSL::X509::Certificate.new
    ca_cert.version = 2
    ca_cert.serial = 1
    ca_cert.subject = ca_name
    ca_cert.issuer = ca_name
    ca_cert.public_key = ca_key
    ca_cert.not_before = Time.now - 60
    ca_cert.not_after = Time.now + 3600
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = ca_cert
    ef.issuer_certificate = ca_cert
    ca_cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
    ca_cert.add_extension(ef.create_extension("keyUsage", "keyCertSign,cRLSign", true))
    ca_cert.sign(ca_key, "sha256")

    key = OpenSSL::PKey::EC.generate("prime256v1")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 2
    cert.subject = OpenSSL::X509::Name.parse("/CN=127.0.0.1")
    cert.issuer = ca_name
    cert.public_key = key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = ca_cert
    cert.add_extension(ef.create_extension("subjectAltName", "IP:127.0.0.1", false))
    cert.add_extension(ef.create_extension("basicConstraints", "CA:FALSE", true))
    cert.sign(ca_key, "sha256")

    store = OpenSSL::X509::Store.new
    store.add_cert(ca_cert)

    TCPServer.open("127.0.0.1", 0) {|tcpserver|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.key = key
      ctx.cert = cert
      serv = OpenSSL::SSL::SSLServer.new(tcpserver, ctx)
      _, port, _, _ = serv.addr

      client_thread = Thread.new {
        proxy = Net::HTTP.Proxy("127.0.0.1", port, 'user', 'password', true)
        http = proxy.new("foo.example.org", 8000)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        http.cert_store = store
        http.open_timeout = 5
        begin
          http.start
        rescue EOFError, OpenSSL::SSL::SSLError, Errno::ECONNRESET, Errno::EPIPE
        end
      }
      server_thread = Thread.new {
        sock = nil
        begin
          unless tcpserver.wait_readable(5)
            flunk "timed out waiting for the proxy connection"
          end
          sock = serv.accept
          proxy_request = sock.gets("\r\n\r\n")
          assert_equal(
            "CONNECT foo.example.org:8000 HTTP/1.1\r\n" +
            "Host: foo.example.org:8000\r\n" +
            "Proxy-Authorization: Basic dXNlcjpwYXNzd29yZA==\r\n" +
            "\r\n",
            proxy_request)
          sock.print "HTTP/1.1 200 Connection Established\r\n\r\n"
        ensure
          sock.close if sock && !sock.closed?
        end
      }
      assert_join_threads([client_thread, server_thread])
    }
  end
end
