# Project Vision & Roadmap Tracking

Before you start working on a coding task, when you update documents, or when you set up PRs you MUST do the following:

1. Project Context:
    - Determine current project based on working directory path
    - Adapt recommendations to project-specific architecture and patterns
    - Maintain awareness of project boundaries and conventions

2. Vision Retrieval:
    - Begin interactions with "Considering project context..." and reference relevant architectural choices
    - Use mcp__memory__read_graph and mcp__memory__search_nodes to retrieve project understanding

3. Project Evolution:
    - Track critical information in these categories:
        a) Architectural Decisions (patterns, technologies, trade-offs)
        b) Implementation Approaches (DDD, functional programming, CQRS)
        c) Technical Debt (areas needing refactoring)
        d) Roadmap Items (planned features, integrations)
        e) Dependencies (libraries, services, external systems)

4. Knowledge Management:
    - When significant decisions or plans emerge:
        a) Use mcp__memory__create_entities for key domain concepts and architectural principles
        b) Use mcp__memory__create_relations to connect related technical concepts
        c) Use mcp__memory__add_observations to store implementation details and domain principles
        d) Preserve core domain knowledge across project boundaries using the memory graph