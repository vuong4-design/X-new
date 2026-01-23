#include "fishhook.h"
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <stdint.h>
#include <string.h>

#ifdef __LP64__
typedef struct mach_header_64 mach_header_t;
typedef struct segment_command_64 segment_command_t;
typedef struct section_64 section_t;
typedef struct nlist_64 nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT_64
#else
typedef struct mach_header mach_header_t;
typedef struct segment_command segment_command_t;
typedef struct section section_t;
typedef struct nlist nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT
#endif

static struct rebinding *s_rebindings = NULL;
static size_t s_rebindings_nel = 0;

static void perform_rebinding_with_section(section_t *section,
                                           intptr_t slide,
                                           nlist_t *symtab,
                                           char *strtab,
                                           uint32_t *indirect_symtab) {
  if (!section || section->size == 0) return;

  void **indirect_symbol_bindings = (void **)((uintptr_t)slide + section->addr);
  uint32_t *indirect_symbol_indices = indirect_symtab + section->reserved1;

  for (uint i = 0; i < section->size / sizeof(void *); i++) {
    uint32_t symtab_index = indirect_symbol_indices[i];
    if (symtab_index == (uint32_t)INDIRECT_SYMBOL_ABS ||
        symtab_index == (uint32_t)INDIRECT_SYMBOL_LOCAL ||
        symtab_index == (uint32_t)(INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) {
      continue;
    }

    uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
    if (strtab_offset == 0) continue;

    char *symbol_name = strtab + strtab_offset;
    if (!symbol_name || symbol_name[0] != '_') continue;

    for (size_t j = 0; j < s_rebindings_nel; j++) {
      if (strcmp(&symbol_name[1], s_rebindings[j].name) == 0) {
        if (s_rebindings[j].replaced && *s_rebindings[j].replaced == NULL) {
          *s_rebindings[j].replaced = indirect_symbol_bindings[i];
        }
        indirect_symbol_bindings[i] = s_rebindings[j].replacement;
        break;
      }
    }
  }
}

static void rebind_symbols_for_image(const struct mach_header *header, intptr_t slide) {
  segment_command_t *linkedit_segment = NULL;
  struct symtab_command *symtab_cmd = NULL;
  struct dysymtab_command *dysymtab_cmd = NULL;

  uintptr_t cur = (uintptr_t)header + sizeof(mach_header_t);

  for (uint i = 0; i < header->ncmds; i++) {
    struct load_command *lc = (struct load_command *)cur;
    if (lc->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
      segment_command_t *seg = (segment_command_t *)lc;
      if (strcmp(seg->segname, SEG_LINKEDIT) == 0) linkedit_segment = seg;
    } else if (lc->cmd == LC_SYMTAB) {
      symtab_cmd = (struct symtab_command *)lc;
    } else if (lc->cmd == LC_DYSYMTAB) {
      dysymtab_cmd = (struct dysymtab_command *)lc;
    }
    cur += lc->cmdsize;
  }

  if (!linkedit_segment || !symtab_cmd || !dysymtab_cmd) return;

  uintptr_t linkedit_base = (uintptr_t)slide + linkedit_segment->vmaddr - linkedit_segment->fileoff;
  nlist_t *symtab = (nlist_t *)(linkedit_base + symtab_cmd->symoff);
  char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);
  uint32_t *indirect_symtab = (uint32_t *)(linkedit_base + dysymtab_cmd->indirectsymoff);

  cur = (uintptr_t)header + sizeof(mach_header_t);
  for (uint i = 0; i < header->ncmds; i++) {
    struct load_command *lc = (struct load_command *)cur;
    if (lc->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
      segment_command_t *seg = (segment_command_t *)lc;

      if (strcmp(seg->segname, SEG_DATA) != 0 && strcmp(seg->segname, "__DATA_CONST") != 0) {
        cur += lc->cmdsize;
        continue;
      }

      section_t *sect = (section_t *)(cur + sizeof(segment_command_t));
      for (uint j = 0; j < seg->nsects; j++) {
        uint32_t type = sect[j].flags & SECTION_TYPE;
        if (type == S_LAZY_SYMBOL_POINTERS || type == S_NON_LAZY_SYMBOL_POINTERS) {
          perform_rebinding_with_section(&sect[j], slide, symtab, strtab, indirect_symtab);
        }
      }
    }
    cur += lc->cmdsize;
  }
}

static void _rebind_callback(const struct mach_header *mh, intptr_t slide) {
  rebind_symbols_for_image(mh, slide);
}

int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel) {
  s_rebindings = rebindings;
  s_rebindings_nel = rebindings_nel;

  uint32_t c = _dyld_image_count();
  for (uint32_t i = 0; i < c; i++) {
    rebind_symbols_for_image(_dyld_get_image_header(i), _dyld_get_image_vmaddr_slide(i));
  }

  _dyld_register_func_for_add_image(_rebind_callback);
  return 0;
}
