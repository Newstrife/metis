# Hotwire / Turbo / Stimulus Patterns

Rails 8 + Hotwire best practices.

## Turbo Streams

### Standard CRUD Response Pattern

**Controller**: Respond with `format.turbo_stream` to auto-render the matching view template.

```ruby
class CommentsController < ApplicationController
  def create
    @comment = @post.comments.create!(comment_params)

    respond_to do |format|
      format.turbo_stream  # Renders create.turbo_stream.erb
      format.html { redirect_to @post }
    end
  end

  def update
    @comment.update!(comment_params)

    respond_to do |format|
      format.turbo_stream  # Renders update.turbo_stream.erb
      format.html { redirect_to @post }
    end
  end

  def destroy
    @comment.destroy

    respond_to do |format|
      format.turbo_stream  # Renders destroy.turbo_stream.erb
      format.html { redirect_to @post }
    end
  end
end
```

**Turbo Stream Templates** (`create.turbo_stream.erb`, `update.turbo_stream.erb`, `destroy.turbo_stream.erb`):

```erb
<%# create.turbo_stream.erb - Append new comment and reset form %>
<%= turbo_stream.before [ @post, :new_comment ], partial: "comments/comment", locals: { comment: @comment } %>
<%= turbo_stream.update [ @post, :new_comment ], partial: "comments/form", locals: { post: @post } %>

<%# update.turbo_stream.erb - Replace comment with updated content %>
<%= turbo_stream.replace dom_id(@comment), partial: "comments/comment", locals: { comment: @comment } %>

<%# destroy.turbo_stream.erb - Remove comment from DOM %>
<%= turbo_stream.remove dom_id(@comment) %>
```

### Available Stream Actions

Only use the standard 7 actions. Never register custom actions.

| Action | Usage |
|--------|-------|
| `append` | Add inside container, after existing content |
| `prepend` | Add inside container, before existing content |
| `before` | Insert before target |
| `after` | Insert after target |
| `replace` | Replace target entirely |
| `update` | Update target's inner HTML |
| `remove` | Remove target from DOM |

### Morph Mode (Turbo 8+)

Use `method: :morph` for efficient DOM updates that preserve focus and input state.

```erb
<%= turbo_stream.replace dom_id(@card, :container),
      partial: "cards/container",
      method: :morph,
      locals: { card: @card.reload } %>
```

### Job Broadcasting (Real-time Updates)

```ruby
Turbo::StreamsChannel.broadcast_replace_to(
  "conversation_#{conversation.id}",
  target: "message_#{message.id}",
  partial: "messages/message",
  locals: { message: message }
)
```

Subscribe in views with `<%= turbo_stream_from @conversation %>`.

---

## Turbo Frames

### Basic Frame

Scope navigation to a frame — only the frame's content is replaced.

```erb
<%= turbo_frame_tag "inbox-main" do %>
  <!-- Content replaced on navigation -->
<% end %>
```

### Edit In-Place Pattern

The canonical pattern for inline editing without leaving the page.

**Display partial** (`_comment.html.erb`):
```erb
<div id="<%= dom_id(comment) %>">
  <%= turbo_frame_tag comment, :edit do %>
    <p><%= comment.body %></p>
    <%= link_to "Edit", edit_comment_path(comment),
          data: { turbo_frame: dom_id(comment, :edit) } %>
  <% end %>
</div>
```

**Edit view** (`edit.html.erb`):
```erb
<%= turbo_frame_tag @comment, :edit do %>
  <%= form_with model: @comment do |form| %>
    <%= form.text_area :body, autofocus: true %>
    <%= form.button "Save" %>
    <%= link_to "Cancel", comment_path(@comment) %>
  <% end %>
<% end %>
```

When "Edit" is clicked, the link targets the frame with `data: { turbo_frame: dom_id(comment, :edit) }`, replacing the frame content with the edit form. Submitting the form renders `update.turbo_stream.erb` which replaces the frame with the updated display.

### Breaking Out of Frames (Full-Page Navigation)

**Use `target: "_top"` on the frame declaration** — this is the standard, built-in way.

```erb
<%= turbo_frame_tag "my_form", target: "_top", src: edit_path(@record) do %>
  <!-- Form submissions that redirect will navigate full page -->
<% end %>
```

When a frame has `target: "_top"`, any redirect from within that frame breaks out to the full page automatically.

```ruby
# Controller uses standard redirect
def update
  @record.update!(record_params)
  redirect_to @record  # Full page navigation due to target="_top"
end
```

**Button/form level breakout**:

```erb
<%= button_to record_path(record), method: :delete,
      form: { data: { turbo_frame: "_top" } } do %>
  Delete
<% end %>
```

### Lazy Loading Frames

Defer frame content loading until visible.

```erb
<%= turbo_frame_tag "picker", src: path, loading: :lazy do %>
<% end %>
```

### Frame IDs

Use `dom_id` for consistent, unique IDs.

```erb
<%# Single resource %>
<%= turbo_frame_tag dom_id(@comment) %>

<%# Nested resource with context %>
<%= turbo_frame_tag [ @post, :new_comment ] %>

<%# Named frame on resource %>
<%= turbo_frame_tag @comment, :edit %>
<%# Outputs: <turbo-frame id="comment_123_edit"> %>
```

---

## Form Patterns

### Standard Form Structure

```erb
<%= form_with model: [@post, Comment.new],
              url: post_comments_path(@post),
              data: { controller: "autoresize form" } do |form| %>
  <%= form.text_area :body, required: true, autofocus: true,
        data: { action: "keydown.enter->form#submit:prevent" } %>
  <%= form.button "Post", data: { form_target: "submit" } %>
<% end %>
```

### Form Lifecycle Events

```erb
<%= form_with ... do |form| %>
  <%# Standard lifecycle actions %>
  <%# turbo:submit-start - fires when form submission begins %>
  <%# turbo:submit-end - fires when form submission completes %>
  <%# turbo:before-fetch-request - fires before network request %>
  <%# turbo:before-fetch-response - fires after response received %>

  <%= form.submit "Save",
        data: {
          action: "turbo:submit-start->form#onStart turbo:submit-end->form#onEnd"
        } %>
<% end %>
```

### JavaScript Form Submission

Use `requestSubmit()` instead of `submit()` to respect Turbo interception.

```javascript
// In Stimulus controller
submit() {
  this.element.requestSubmit()  // Correct - Turbo intercepts this
}

// NOT this
this.element.submit()  // Wrong - bypasses Turbo
```

---

## Stimulus Controllers

Located in `app/javascript/controllers/`. Small, focused, with targets and values.

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "submit"]
  static values = { content: String }
  static outlets = ["other-controller"]

  connect() {
    // Setup on DOM attach
  }

  disconnect() {
    // Cleanup on DOM detach
  }

  handleEvent(event) {
    // Action handler
  }
}
```

### Key Patterns

- **Targets**: DOM element references (`data-controller-target="name"`)
- **Values**: Data attributes (`data-controller-name-value="..."`)
- **Outlets**: Cross-controller communication (`data-controller-other-controller-outlet="..."`)
- **Actions**: Event mapping (`data-action="click->controller#method"`)

---

## Real-Time Updates

### Subscribing to Updates

```erb
<%= turbo_stream_from @conversation %>
<%= turbo_stream_from @conversation, :messages %>
```

### Broadcasting from Jobs

```ruby
class MessageCreatedJob < ApplicationJob
  def perform(message)
    Turbo::StreamsChannel.broadcast_append_to(
      "conversation_#{message.conversation_id}",
      target: "messages",
      partial: "messages/message",
      locals: { message: message }
    )
  end
end
```

---

## Best Practices Summary

| Pattern | Do | Don't |
|---------|-----|-------|
| **Stream actions** | Use standard 7 actions | Register custom actions |
| **Controller response** | `format.turbo_stream` → auto-render template | Inline `render turbo_stream: ...` |
| **Frame IDs** | `dom_id(resource)` or `[ @parent, :child ]` | Hardcoded string IDs |
| **Frame breakout** | `target: "_top"` on frame declaration | Custom `visit` stream action |
| **DOM updates** | `method: :morph` for efficiency | Default replace |
| **Form submission** | `requestSubmit()` in JS | `submit()` in JS |
| **Permanent elements** | `data-turbo-permanent` | Recreate on each update |
