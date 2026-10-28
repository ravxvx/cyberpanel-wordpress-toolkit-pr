#!/bin/sh
# Adds (or refreshes) the "WP Toolkit Pro" sidebar link in CyberPanel's template.
# The link is written in a "safe" form: if the plugin's URL ever disappears (e.g. after a CyberPanel
# upgrade resets urls.py) the link is simply not shown instead of breaking every panel page.
# Safe to run any time:   sh /usr/local/CyberCP/wordpressToolkitPro/repair-menu.sh && systemctl restart lscpd
IDX="${1:-/usr/local/CyberCP/baseTemplate/templates/baseTemplate/index.html}"
[ -f "$IDX" ] || { echo "Template not found: $IDX"; exit 1; }
LINK="{# WPT-BEGIN #}{% url 'wordpressToolkitPro' as wpt_url %}{% if wpt_url %}<a href=\"{{ wpt_url }}\" class=\"menu-item\"><div class=\"icon-wrapper\"><i class=\"fas fa-download\"></i></div><span>WP Toolkit Pro</span></a>{% endif %}{# WPT-END #}"
# remove older versions of our link (single-line safe form, and the legacy multi-line unguarded form)
sed -i '/WPT-BEGIN/d' "$IDX"
if grep -q "{% url 'wordpressToolkitPro' %}\" class=\"menu-item\"" "$IDX" && grep -q '</a>' "$IDX"; then
  sed -i "/{% url 'wordpressToolkitPro' %}\" class=\"menu-item\"/,/<\/a>/d" "$IDX"
fi
for TARGET in "url 'ListWPSites' %}\" class=\"menu-item\"" "url 'listWebsites' %}\" class=\"menu-item\""; do
  if grep -q "$TARGET" "$IDX"; then
    sed -i "/$TARGET/i $LINK" "$IDX"
    break
  fi
done
if grep -q "WPT-BEGIN" "$IDX"; then echo "Sidebar link added."; else echo "WARNING: could not add the link; open /wordpressToolkitPro/ directly."; exit 1; fi
