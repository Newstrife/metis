namespace :docker do
  desc "Build the pi runtime image for Agent::Runtime::Docker. Usage: rake docker:image[name]"
  task :image, [ :name ] => :environment do |_task, args|
    name = args.fetch(:name, "metis-pi")
    context = Rails.root.join("docker/pi-runtime")
    pi_version = PiAgent::SUPPORTED_PI_VERSION

    puts "Building Docker image '#{name}' with pi #{pi_version}..."

    ok = system(
      "docker", "build",
      "--build-arg", "PI_VERSION=#{pi_version}",
      "--tag", name,
      context.to_s
    )
    abort "docker build failed" unless ok

    puts
    puts "Built Docker image '#{name}'."
    puts "Point Metis at it:  export METIS_DOCKER_IMAGE=#{name}"
    puts "                    export METIS_AGENT_RUNTIME=docker"
  end
end
