module AvatarHelper
  # Renders an avatar for the given user at the given pixel size.
  # Resolution order is `User#avatar_source`:
  #   - `:uploaded` → an <img> served from Active Storage, resized 2x
  #     for HiDPI displays via `resize_to_fill`
  #   - `:external` → an <img> pointing at the OAuth-provider URL
  #     cached on the user; `referrerpolicy=no-referrer` so the
  #     provider can't see which page is requesting the image
  #   - `:initials` → the existing gradient <div> with initials
  #
  # `css` defaults to `"avatar"` so the existing CSS class applies
  # to both <img> and <div> forms (see app/assets/tailwind for the
  # shared rules).
  def avatar_for(user, size: 32, css: "avatar")
    case user.avatar_source
    when :uploaded
      target = size * 2
      image_tag(
        user.avatar.variant(resize_to_fill: [ target, target ]),
        width: size, height: size, class: css, alt: "", loading: "lazy"
      )
    when :external
      image_tag(
        user.avatar_url,
        width: size, height: size, class: css, alt: "",
        loading: "lazy", referrerpolicy: "no-referrer"
      )
    else
      content_tag(:div, user.initials, class: css, "aria-hidden": "true")
    end
  end
end
