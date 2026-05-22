namespace :e2b do
  desc "Build the E2B template with pi baked in (needs E2B_API_KEY). Usage: rake e2b:template[name]"
  task :template, [ :name ] => :environment do |_task, args|
    name = args.fetch(:name, "metis-pi")
    pi_package = "@earendil-works/pi-coding-agent@#{PiAgent::SUPPORTED_PI_VERSION}"

    puts "Building E2B template '#{name}' with #{pi_package}..."

    # The MCP connector bridge (pi-mcp-adapter) is baked in alongside pi.
    # Keep the version in sync with bin/setup and docker/pi-runtime/Dockerfile.
    template = E2B::Template.new
                            .from_node_image
                            .npm_install(pi_package, g: true)
                            .run_cmd("pi install npm:pi-mcp-adapter@2.6.1")

    # tags must be a non-null array — the E2B v3 build API rejects null.
    info = E2B::Template.build(template, name: name, tags: [], on_build_logs: ->(line) { puts line })

    puts
    puts "Built E2B template '#{name}' (template_id: #{info.template_id})."
    puts "Point Metis at it:  export METIS_E2B_TEMPLATE=#{name}"
  end
end
