module Agent
  # Curated marketplace listing surfaced on /settings/skills (Marketplace
  # tab). Entries point at directories in the Anthropic skills repo
  # (https://github.com/anthropics/skills). Importing pulls the dir via
  # Agent::SkillImporter and creates a team Skill row.
  module SkillMarketplace
    Entry = Struct.new(:source, :label, :description, keyword_init: true)

    FEATURED = [
      Entry.new(source: "anthropics/skills/skills/pdf",
                label: "PDF",
                description: "Read, extract, fill PDF forms; OCR scanned PDFs."),
      Entry.new(source: "anthropics/skills/skills/xlsx",
                label: "Excel (xlsx)",
                description: "Read, edit, clean, and create Excel spreadsheets."),
      Entry.new(source: "anthropics/skills/skills/docx",
                label: "Word (docx)",
                description: "Create and edit Word documents."),
      Entry.new(source: "anthropics/skills/skills/pptx",
                label: "PowerPoint (pptx)",
                description: "Build and read PowerPoint decks."),
      Entry.new(source: "anthropics/skills/skills/canvas-design",
                label: "Canvas design",
                description: "Visual art in PNG and PDF using design philosophy."),
      Entry.new(source: "anthropics/skills/skills/frontend-design",
                label: "Frontend design",
                description: "Distinctive, production-grade frontend interfaces."),
      Entry.new(source: "anthropics/skills/skills/mcp-builder",
                label: "MCP builder",
                description: "Build high-quality MCP servers in Python or Node."),
      Entry.new(source: "anthropics/skills/skills/doc-coauthoring",
                label: "Doc co-authoring",
                description: "Structured workflow for collaborative documentation."),
      Entry.new(source: "anthropics/skills/skills/internal-comms",
                label: "Internal comms",
                description: "Status reports, leadership updates, FAQs."),
      Entry.new(source: "anthropics/skills/skills/skill-creator",
                label: "Skill creator",
                description: "Create, improve, and benchmark skills."),
      Entry.new(source: "anthropics/skills/skills/brand-guidelines",
                label: "Brand guidelines",
                description: "Apply Anthropic's brand to artifacts.")
    ].freeze
  end
end
