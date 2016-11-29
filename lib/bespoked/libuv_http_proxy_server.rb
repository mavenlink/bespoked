#

module Bespoked
  class LibUVHttpProxyServer
    attr_accessor :run_loop

    def initialize(run_loop_in, options={})
      self.run_loop = run_loop_in

      options[:BindAddress] = DEFAULT_LIBUV_SOCKET_BIND

      #@run_loop.log(:info, :rack_options, [options])

      server = @run_loop.tcp

      server.catch do |reason|
        #@run_loop.log(:error, :rack_http_proxy_handler, [reason, reason.class])
      end

      server.bind(options[:BindAddress], options[:Port].to_i) do |client|
        handle_client(client)
      end

      server.listen(16)
    end

    def handle_client(client)
      http_parser = Http::Parser.new
      reading_state = :request_to_proxy

      http_parser.on_headers_complete = proc do
        reading_state = :request_to_upstream

        env = {"HTTP_HOST" => (http_parser.headers["host"] || http_parser.headers["Host"])}

        in_url = URI.parse("http://" + env["HTTP_HOST"])
        out_url = nil

        if mapped_host_port = @vhosts[in_url.host]
          out_url = URI.parse("http://" + mapped_host_port)
        end

        #TODO
        if url = out_url
          host = url.host
          port = url.port

          #run_loop.log(:warn, :rack_http_on_headers_complete, [http_parser.http_method, http_parser.request_url, host, port])

          on_dns_bad = proc { |err|
            #run_loop.log(:warn, :dns_error, [err, err.class])

            client.close
          }

          on_dns_ok = proc { |addrinfo|
            ip_address = addrinfo[0][0]

            #run_loop.log(:info, :ip_lookup, [host, ip_address, port.to_i, client.sockname, client.peername])

            new_client = run_loop.tcp

            new_client.catch do |err|
              #run_loop.log(:warn, :rack_proxy_client_error, [err, err.class])

              client.close
            end

            new_client.connect(ip_address, port.to_i) do |up_client|
              up_client.write("#{http_parser.http_method} #{http_parser.request_url} HTTP/1.1\r\n")

              proxy_override_headers = {
                "Connection" => "close",
                "X-Forwarded-For" => client.peername[0] || "", # NOTE: makes the actual IP available
                "X-Request-Start" => "t=#{Time.now.to_f}", # track queue time in newrelic
                "X-Forwarded-Host" => "", # NOTE: this is important to pevent host poisoning
                "Client-IP" => "" # strip Client-IP header to prevent rails spoofing error
              }

              if ENV["MOCK_X_FORWARDED_PROTO"]
                proxy_override_headers["X-Forwarded-Proto"] = ENV["MOCK_X_FORWARDED_PROTO"] # NOTE: this is what allows unicorn to not be SSL, assumed SSL termination elsewhere
              end

              headers_for_upstream_request = http_parser.headers.merge(proxy_override_headers)

              headers_for_upstream_request.each { |k, vs|
                vs.split("\n").each { |v|
                  if k && v
                    up_client.write "#{k}: #{v}\r\n"
                  end
                }
              }

              #run_loop.log(:debug, :wrote_upstream_request, [headers_for_upstream_request])

              #http_parser = nil
              up_client.write("\r\n")
              if http_parser.upgrade_data
                up_client.write(http_parser.upgrade_data)
              end
              http_parser.reset!

              up_client.progress do |chunk|
                if client && chunk && chunk.length > 0
                  client.write(chunk)
                end
              end

              client.progress do |chunk|
                if reading_state == :request_to_upstream
                  if up_client && chunk && chunk.length > 0
                    up_client.write(chunk)
                  end
                end
              end
            end

            new_client.start_read
          }

          do_dns_lookup = proc {
            run_loop.lookup(host, {:wait => false}).then(on_dns_ok, on_dns_bad)
          }

          do_dns_lookup.call
        else
          client.close
        end

        :stop
      end

      ##################

      client.progress do |chunk|
        if http_parser && reading_state == :request_to_proxy
          if chunk && chunk.length > 0
            http_parser << chunk
          end
        end
      end

      client.start_read
    end

    def send_headers(client, status, headers)
      client.write "HTTP/1.1 #{status} #{WEBrick::HTTPStatus.reason_phrase(status)}\r\n"
      headers.each { |k, vs|
        vs.split("\n").each { |v|
          client.write "#{k}: #{v}\r\n"
        }
      }
      client.write "\r\n"
    end

    def send_body(client, body)
      body.each { |part|
        if part && part.length > 0
          client.write part
        end
      }
    end

  end
end