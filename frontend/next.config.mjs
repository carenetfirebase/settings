/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // The API is bound to loopback and never exposed. The dev server proxies so
  // the browser makes same-origin requests and no CORS preflight is needed.
  async rewrites() {
    return [{ source: "/api/:path*", destination: "http://127.0.0.1:8000/api/:path*" }];
  },
};
export default nextConfig;
