require 'ffi'
require 'ffi/tools/const_generator'

class FlexStruct < FFI::Struct
  def read_uint8_from(key, length)
    target_pointer = pointer + layout.offsets.to_h[key]
    target_pointer.read_array_of_uint8(length)
  end
end

module NL
  extend FFI::Library
  ffi_lib 'libnl-3.so.200'
  attach_function :nl_socket_alloc, [], :pointer
  attach_function :nl_socket_get_fd, [:pointer], :int
  attach_function :nl_connect, [:pointer,:int], :int
  attach_function :nlmsg_data, [:pointer], :pointer
  attach_function :nl_send_simple, [:pointer,:int,:int,:pointer,:int], :int
  attach_function :nl_geterror, [:int], :string
  attach_function :nl_socket_disable_seq_check, [:pointer], :void
  attach_function :nlmsg_alloc_simple, [:int, :int], :pointer
  attach_function :nl_socket_disable_auto_ack, [:pointer], :void
  attach_function :nl_socket_enable_msg_peek, [:pointer], :void
  attach_function :nl_recv, [:pointer, :pointer, :pointer, :pointer], :int
  attach_function :nlmsg_ok, [:pointer, :int], :int
  attach_function :nl_cache_mngt_provide, [:pointer], :void

  ['RTM_GETROUTE', 'NETLINK_ROUTE'].each do |const|
    const_set(const,FFI::ConstGenerator.new(nil, :required => true) do |gen|
      gen.include 'linux/netlink.h'
      gen.include 'linux/rtnetlink.h'
      gen.const(const)
    end[const].to_i)
  end

  # nl_cache
  class Cache < FlexStruct
    layout :prev, :pointer,
    :next, :pointer,
    :items_count, :uint,
    :iarg1, :uint,
    :iarg2, :uint,
    :ops, :pointer
    # more but cbf here
    class RouteGenerator
      include Enumerable

      def initialize(cache)
        @cache = cache
        @finish_line = cache.pointer
        @current_pointer = cache[:next]
      end

      def each
        while @current_pointer != @finish_line
          route = NLROUTE::Route.new(@current_pointer)
          @current_pointer = route[:next]
          yield route
        end
      end
    end

    def routes
      #routes = []
      #route_ptr = self[:next]
      #while true
      #  route = NLROUTE::Route.new(route_ptr)
      #  routes << route
      #  break if route_ptr == self[:prev]
      #  route_ptr = route[:next]
      #end

      #routes
      RouteGenerator.new(self).to_a
    end
  end

  #struct nl_addr
  #{
  #  int      a_family;
  #  unsigned int    a_maxsize;
  #  unsigned int    a_len;
  #  int      a_prefixlen;
  #  int      a_refcnt;
  #  char      a_addr[0];
  #};
  class Address < FlexStruct
    layout :a_family, :uint,
    :a_maxsize, :uint,
    :a_len, :uint,
    :a_prefixlen, :uint,
    :a_refcnt, :uint,
    :a_addr, :uint8
  end
end

module NLROUTE
  extend FFI::Library
  ffi_lib 'libnl-route-3.so.200'
  attach_function :rtnl_route_alloc_cache, [:pointer, :int, :int, :pointer], :int

  # we can cheat a little
  # the header points to the offset of the ce_list
  # so we can just start from there and ignore the rest of NLHDR_COMMON http://libnl.sourcearchive.com/documentation/1.1/group__object__api_g0f84d461252a52ed33e307432bd0b3f8.html#g0f84d461252a52ed33e307432bd0b3f8
  # rtnl_route
  # https://github.com/tgraf/libnl-1.1-stable/blob/master/include/netlink-types.h
  class Route < FlexStruct
    layout :prev, :pointer,
    :next, :pointer,
    :ce_msgtype, :uint,
    :ce_flags, :uint,
    :ce_mask, :uint,
    :rt_family, :uint8,
    :rt_dst_len, :uint8,
    :rt_src_len, :uint8,
    :rt_tos, :uint8,
    :rt_table, :uint8,
    :rt_protocol, :uint8,
    :rt_scope, :uint8,
    :rt_type, :uint8,
    :rt_flags, :uint32,
    :rt_dst, :pointer,
    :rt_src, :pointer,
    :rt_iif, [:uint8, 16],
    :rt_oif, :uint32,
    :rt_gateway, :pointer
    #char      rt_iif[IFNAMSIZ];
    #uint32_t    rt_oif;
    #struct nl_addr *  rt_gateway;
    #uint32_t    rt_prio;
    #uint32_t    rt_metrics[RTAX_MAX];
    #uint32_t    rt_metrics_mask;
    #struct nl_addr *  rt_pref_src;
    #struct nl_list_head  rt_nexthops;
    #realm_t      rt_realms;
    #struct rtnl_rtcacheinfo  rt_cacheinfo;
    #uint32_t    rt_mp_algo;
    #uint32_t    rt_flag_mask;
  end
end

# TODO memory management D:
nl = NL.nl_socket_alloc
NL.nl_connect(nl,NL::NETLINK_ROUTE)
NL.nl_socket_disable_auto_ack(nl)
NL.nl_socket_disable_seq_check(nl)
socket=NL.nl_socket_get_fd(nl)
route_cache_ptr = FFI::MemoryPointer.new :pointer
# AF_INET = 2
NLROUTE.rtnl_route_alloc_cache(nl, 2, 0, route_cache_ptr)
# TODO modify reference counts to do it properly
# then we iterate over route_cache?
route_cache = NL::Cache.new(route_cache_ptr.read_pointer)
routes = route_cache.routes
dests = routes.map {|route| NL::Address.new(route[:rt_dst]) }
prefixes = dests.map {|dest| dest.read_uint8_from(:a_addr, 4).join(".") + "/" + dest[:a_prefixlen].to_s }
gateways = routes.map {|route| NL::Address.new(route[:rt_gateway]) }
#gateway_addrs = gateways.map {|gateway| gateway.read_uint8_from(:a_addr, 4).join(".") }
#sample_route = NLROUTE::Route.new(route_cache[:next])
#dst = NL::Address.new(sample_route[:rt_dst])
require 'byebug'
byebug

puts 'lol'
