import { useState } from "react";
import { Link, NavLink, Route, Routes, useLocation } from "react-router-dom";
import {
  Activity,
  Bell,
  BookOpen,
  ChevronDown,
  CircleHelp,
  CreditCard,
  GitBranch,
  LayoutDashboard,
  Link2,
  Menu,
  Network,
  Search,
  Settings,
  ShieldCheck,
  Users,
  X,
} from "lucide-react";

const navigation = [
  { label: "Tổng quan", to: "/", icon: LayoutDashboard },
  { label: "Cây gia phả", to: "/gia-pha/cay", icon: GitBranch },
  { label: "Thành viên", to: "/gia-pha/thanh-vien", icon: Users },
  { label: "Quan hệ", to: "/gia-pha/quan-he", icon: Network },
];

const governance = [
  { label: "Chế độ xem", to: "/quyen-han/che-do-xem", icon: ShieldCheck },
  { label: "Link chia sẻ", to: "/chia-se", icon: Link2 },
  { label: "Nhật ký hoạt động", to: "/nhat-ky", icon: Activity },
  { label: "Gói dịch vụ", to: "/goi-dich-vu", icon: CreditCard },
];

const screens = {
  "/": [
    "Không gian dòng họ",
    "Tổng quan",
    "Theo dõi nhanh dữ liệu, hoạt động và trạng thái không gian gia phả.",
    LayoutDashboard,
  ],
  "/gia-pha/cay": [
    "Gia phả",
    "Cây gia phả",
    "Khám phá các nhánh, thế hệ và quan hệ trong dòng họ.",
    GitBranch,
  ],
  "/gia-pha/thanh-vien": [
    "Gia phả",
    "Thành viên",
    "Danh sách hồ sơ trong dòng họ và quyền truy cập tương ứng.",
    Users,
  ],
  "/gia-pha/quan-he": [
    "Gia phả",
    "Quan hệ gia đình",
    "Quản lý hôn phối, quan hệ con và thứ tự trong gia đình.",
    Network,
  ],
  "/quyen-han/che-do-xem": [
    "Quản trị dòng họ",
    "Chế độ xem",
    "Kiểm soát phạm vi và nhóm thông tin hiển thị cho từng vai trò.",
    ShieldCheck,
  ],
  "/chia-se": [
    "Quản trị dòng họ",
    "Link chia sẻ",
    "Tạo và quản lý các link xem gia phả dành cho khách.",
    Link2,
  ],
  "/nhat-ky": [
    "Quản trị dòng họ",
    "Nhật ký hoạt động",
    "Theo dõi lịch sử truy cập và thay đổi dữ liệu quan trọng.",
    Activity,
  ],
  "/goi-dich-vu": [
    "Tài khoản & thanh toán",
    "Gói dịch vụ",
    "Xem hạn mức, tính năng đang dùng và lịch sử thanh toán.",
    CreditCard,
  ],
  "/cai-dat": [
    "Không gian dòng họ",
    "Cài đặt",
    "Cấu hình dòng họ, thông báo và thông tin tài khoản.",
    Settings,
  ],
  "/quan-tri": [
    "Quản trị nền tảng",
    "Quản trị hệ thống",
    "Quản lý tài khoản, dòng họ, gói dịch vụ và cấu hình nền tảng.",
    ShieldCheck,
  ],
};

function SidebarLink({ item, onNavigate }) {
  const Icon = item.icon;
  return (
    <NavLink
      to={item.to}
      onClick={onNavigate}
      end={item.to === "/"}
      className={({ isActive }) =>
        `group flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm transition ${isActive ? "bg-[#e7f0ed] font-semibold text-[#17594f]" : "text-[#65716e] hover:bg-[#f3f6f4] hover:text-[#233c37]"}`
      }
    >
      <Icon size={18} strokeWidth={1.8} />
      <span>{item.label}</span>
    </NavLink>
  );
}

function PagePlaceholder({ config }) {
  const [eyebrow, title, description, Icon] = config;
  const stats = [
    ["Đang theo dõi", "24", "Cập nhật hôm nay"],
    ["Cần rà soát", "08", "Trong phạm vi của bạn"],
    ["Hoạt động gần đây", "16", "7 ngày vừa qua"],
  ];

  return (
    <div className="animate-rise space-y-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="mb-2 text-xs font-bold uppercase tracking-[0.16em] text-[#b16c43]">
            {eyebrow}
          </p>
          <h1 className="font-display text-4xl font-semibold tracking-tight text-[#183b35]">
            {title}
          </h1>
          <p className="mt-2 max-w-2xl text-sm text-[#6b7773]">{description}</p>
        </div>
        <button className="hidden rounded-xl bg-[#17594f] px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:bg-[#10483f] sm:block">
          + Thêm mới
        </button>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        {stats.map(([label, value, hint]) => (
          <div
            key={label}
            className="rounded-2xl border border-[#dce7e2] bg-white p-5 shadow-[0_8px_24px_rgba(28,67,58,0.04)]"
          >
            <p className="text-sm text-[#788681]">{label}</p>
            <p className="mt-3 font-display text-3xl font-semibold text-[#183b35]">
              {value}
            </p>
            <p className="mt-1 text-xs text-[#9aa6a2]">{hint}</p>
          </div>
        ))}
      </div>

      <div className="grid gap-5 lg:grid-cols-[1.5fr_1fr]">
        <div className="min-h-72 rounded-2xl border border-[#dce7e2] bg-white p-6 shadow-[0_8px_24px_rgba(28,67,58,0.04)]">
          <div className="flex items-center gap-3 border-b border-[#edf1ef] pb-4">
            <div className="rounded-xl bg-[#edf5f1] p-2.5 text-[#17594f]">
              <Icon size={20} />
            </div>
            <div>
              <h2 className="font-semibold text-[#24443d]">Khu vực nội dung</h2>
              <p className="text-xs text-[#87938f]">
                Placeholder cho dữ liệu và thao tác của màn hình
              </p>
            </div>
          </div>
          <div className="flex h-48 items-center justify-center text-center">
            <div>
              <p className="font-display text-lg font-semibold text-[#48635c]">
                Sẵn sàng kết nối API
              </p>
              <p className="mt-1 text-sm text-[#899792]">
                Các thành phần nghiệp vụ sẽ được bổ sung ở bước tiếp theo.
              </p>
            </div>
          </div>
        </div>
        <div className="rounded-2xl border border-[#eadfd6] bg-[#fffaf5] p-6">
          <p className="text-xs font-bold uppercase tracking-[0.14em] text-[#b16c43]">
            Màn hình trong kế hoạch
          </p>
          <ul className="mt-5 space-y-3 text-sm text-[#536762]">
            <li className="flex gap-3">
              <span className="mt-1 h-2 w-2 shrink-0 rounded-full bg-[#d58a5d]" />
              Kết nối đặc tả OpenAPI
            </li>
            <li className="flex gap-3">
              <span className="mt-1 h-2 w-2 shrink-0 rounded-full bg-[#d58a5d]" />
              Phân quyền theo vai trò và phạm vi
            </li>
            <li className="flex gap-3">
              <span className="mt-1 h-2 w-2 shrink-0 rounded-full bg-[#d58a5d]" />
              Hiển thị dữ liệu theo gói dịch vụ
            </li>
          </ul>
        </div>
      </div>
    </div>
  );
}

function App() {
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const location = useLocation();
  const activeScreen = screens[location.pathname] ?? screens["/"];

  return (
    <div className="min-h-screen bg-[#f6f8f6] text-[#183b35]">
      <aside
        className={`fixed inset-y-0 left-0 z-30 flex w-64 flex-col border-r border-[#dce7e2] bg-[#fbfcfb] px-4 py-5 transition-transform lg:translate-x-0 ${sidebarOpen ? "translate-x-0" : "-translate-x-full"}`}
      >
        <div className="flex items-center justify-between px-2">
          <Link
            to="/"
            className="flex items-center gap-3"
            onClick={() => setSidebarOpen(false)}
          >
            <div className="flex h-10 w-10 items-center justify-center rounded-2xl bg-[#17594f] text-lg font-bold text-[#f5d7ac]">
              K
            </div>
            <div>
              <p className="font-display text-base font-bold text-[#17594f]">
                Khai Chi
              </p>
              <p className="text-[10px] uppercase tracking-[0.18em] text-[#9a6a4b]">
                Tán Diệp
              </p>
            </div>
          </Link>
          <button
            className="rounded-lg p-2 text-[#71817b] lg:hidden"
            onClick={() => setSidebarOpen(false)}
            aria-label="Đóng menu"
          >
            <X size={18} />
          </button>
        </div>
        <div className="mt-8 flex-1 overflow-y-auto">
          <p className="px-3 text-[10px] font-bold uppercase tracking-[0.18em] text-[#a3ada9]">
            Không gian dòng họ
          </p>
          <nav className="mt-3 space-y-1">
            {navigation.map((item) => (
              <SidebarLink
                key={item.to}
                item={item}
                onNavigate={() => setSidebarOpen(false)}
              />
            ))}
          </nav>
          <p className="mt-8 px-3 text-[10px] font-bold uppercase tracking-[0.18em] text-[#a3ada9]">
            Quản trị & chia sẻ
          </p>
          <nav className="mt-3 space-y-1">
            {governance.map((item) => (
              <SidebarLink
                key={item.to}
                item={item}
                onNavigate={() => setSidebarOpen(false)}
              />
            ))}
          </nav>
        </div>
        <div className="border-t border-[#e6ece9] pt-4">
          <SidebarLink
            item={{ label: "Cài đặt", to: "/cai-dat", icon: Settings }}
            onNavigate={() => setSidebarOpen(false)}
          />
          <div className="mt-3 flex items-center gap-3 rounded-xl bg-[#f0f5f2] p-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-full bg-[#d5e5dd] text-sm font-bold text-[#17594f]">
              NA
            </div>
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold text-[#31534a]">
                Nguyễn An
              </p>
              <p className="text-xs text-[#82908b]">Trưởng tộc</p>
            </div>
            <ChevronDown size={15} className="ml-auto text-[#82908b]" />
          </div>
        </div>
      </aside>

      {sidebarOpen && (
        <button
          className="fixed inset-0 z-20 bg-[#183b35]/30 lg:hidden"
          onClick={() => setSidebarOpen(false)}
          aria-label="Đóng menu"
        />
      )}
      <div className="lg:pl-64">
        <header className="sticky top-0 z-10 flex h-19 items-center justify-between border-b border-[#e1e9e5] bg-[#fbfcfb]/90 px-5 backdrop-blur-md sm:px-8">
          <div className="flex items-center gap-3">
            <button
              className="rounded-xl p-2 text-[#536b63] hover:bg-[#edf3f0] lg:hidden"
              onClick={() => setSidebarOpen(true)}
              aria-label="Mở menu"
            >
              <Menu size={21} />
            </button>
            <div className="hidden items-center gap-2 text-sm text-[#7b8984] sm:flex">
              <BookOpen size={16} /> Không gian của tôi{" "}
              <span className="text-[#b2bdb9]">/</span>{" "}
              <span className="font-semibold text-[#37574f]">Họ Nguyễn</span>
            </div>
          </div>
          <div className="flex items-center gap-2 sm:gap-4">
            <div className="hidden items-center gap-2 rounded-xl border border-[#e0e8e4] bg-white px-3 py-2 text-sm text-[#9aa6a2] md:flex">
              <Search size={16} />
              Tìm kiếm trong gia phả
            </div>
            <button
              className="rounded-xl p-2.5 text-[#60736b] hover:bg-[#edf3f0]"
              aria-label="Trợ giúp"
            >
              <CircleHelp size={19} />
            </button>
            <button
              className="relative rounded-xl p-2.5 text-[#60736b] hover:bg-[#edf3f0]"
              aria-label="Thông báo"
            >
              <Bell size={19} />
              <span className="absolute right-2 top-2 h-1.5 w-1.5 rounded-full bg-[#c9784e]" />
            </button>
          </div>
        </header>
        <main className="mx-auto max-w-360 px-5 py-8 sm:px-8 lg:px-10">
          <Routes>
            {Object.entries(screens).map(([path, config]) => (
              <Route
                key={path}
                path={path}
                element={<PagePlaceholder config={config} />}
              />
            ))}
          </Routes>
          {!screens[location.pathname] && (
            <PagePlaceholder config={activeScreen} />
          )}
        </main>
      </div>
    </div>
  );
}

export default App;
