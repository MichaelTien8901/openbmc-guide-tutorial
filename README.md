# OpenBMC Guide Tutorial

A comprehensive guide for OpenBMC development - from beginner to professional.

**Live Site:** https://michaeltien8901.github.io/openbmc-guide-tutorial/

## Deploy Instructions

### Automatic Deployment (GitHub Pages)

The site automatically deploys to GitHub Pages when you push to the `master` branch.

```bash
# Make changes, commit, and push
git add .
git commit -m "Your changes"
git push origin master
```

The GitHub Actions workflow (`.github/workflows/pages.yml`) will:
1. Build the Jekyll site
2. Deploy to GitHub Pages
3. Site available at https://michaeltien8901.github.io/openbmc-guide-tutorial/

**First-time setup:** Enable GitHub Pages in repository settings:
1. Go to Settings → Pages
2. Source: Select "GitHub Actions"

### Local Development

#### Prerequisites

- Ruby 3.2+
- Bundler

#### Setup

```bash
# Clone the repository
git clone https://github.com/MichaelTien8901/openbmc-guide-tutorial.git
cd openbmc-guide-tutorial

# Install dependencies
bundle install

# Start local server
bundle exec jekyll serve
```

Site will be available at http://localhost:4000/openbmc-guide-tutorial/

#### Live Reload

```bash
bundle exec jekyll serve --livereload
```

### Docker Development

```bash
# Build and run with Docker
docker run --rm -it \
  -v "$PWD:/srv/jekyll" \
  -p 4000:4000 \
  jekyll/jekyll:4.3 \
  jekyll serve --host 0.0.0.0
```

### Manual Build

```bash
# Build static files
bundle exec jekyll build

# Output in _site/ directory
ls _site/
```

The `_site/` directory can be deployed to any static hosting service.

### Deploy to Other Platforms

#### Netlify

1. Connect your GitHub repository
2. Build command: `bundle exec jekyll build`
3. Publish directory: `_site`

#### Vercel

1. Import your GitHub repository
2. Framework preset: Jekyll
3. Build command: `bundle exec jekyll build`
4. Output directory: `_site`

#### Self-hosted (Nginx)

```bash
# Build the site
bundle exec jekyll build

# Copy to web server
sudo cp -r _site/* /var/www/html/openbmc-guide/

# Nginx config
server {
    listen 80;
    server_name your-domain.com;
    root /var/www/html/openbmc-guide;
    index index.html;
}
```

## Project Structure

```
openbmc-guide-tutorial/
├── docs/                    # Documentation pages
│   ├── 01-getting-started/  # Getting started guides
│   ├── 02-architecture/     # Architecture documentation
│   ├── 03-core-services/    # Core services guides
│   ├── 04-interfaces/       # Interface guides (IPMI, Redfish, etc.)
│   ├── 05-advanced/         # Advanced topics
│   └── 06-porting/          # Platform porting guides
├── examples/                # Code examples
├── assets/                  # Images and static assets
├── _config.yml              # Jekyll configuration
├── Gemfile                  # Ruby dependencies
└── .github/workflows/       # CI/CD workflows
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Content is provided for educational purposes. Not affiliated with the OpenBMC project.
