#

module Bespoked
  class ProxyController
    attr_accessor :run_loop,
                  :controller,
                  :vhosts

    def initialize(run_loop_in, controller_in)
      self.run_loop = run_loop_in
      self.controller = controller_in
      self.vhosts = {}
    end

    def install(ingress_descriptions)
      #@run_loop.log(:info, :proxy_controller_install, ingress_descriptions.keys)

      ingress_descriptions.values.each do |ingress_description|
        vhosts_for_ingress = self.extract_vhosts(ingress_description)
        #@run_loop.log(:info, :vhosts_extracted, vhosts_for_ingress)
        vhosts_for_ingress.each do |host, service_name, upstreams|
          #@run_loop.log(:info, :rack_proxy_vhost, [host, service_name, upstreams])
          @vhosts[host] = upstreams[0]
        end
      end
    end

    def extract_name(description)
      if metadata = description["metadata"]
        metadata["name"]
      end
    end

    def extract_vhosts(description)
      ingress_name = self.extract_name(description)
      spec_rules = description["spec"]["rules"]

      vhosts = []

      spec_rules.each do |rule|
        rule_host = rule["host"]
        if http = rule["http"]
          http["paths"].each do |http_path|
            service_name = http_path["backend"]["serviceName"]
            if @controller && service = @controller.locate_service(service_name)
              if spec = service["spec"]
                upstreams = []
                if ports = spec["ports"]
                  ports.each do |port|
                    upstreams << "%s:%s" % [service_name, port["port"]]
                  end
                end
                if upstreams.length > 0
                  vhosts << [rule_host, service_name, upstreams]
                end
              end
            end
          end
        end
      end

      vhosts
    end
  end
end