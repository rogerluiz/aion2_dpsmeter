"""
nickname_cache.py — Cache de nomes de jogadores e entidades

Gerencia armazenamento de nicknames detectados via parsing de pacotes.
Baseado no A2Tools DPS Meter DataStorage.
"""

import logging
from typing import Dict, Optional, Set

logger = logging.getLogger(__name__)


class NicknameCache:
    """
    Cache de nicknames de jogadores e entidades.

    Suporta:
    - Nicknames confirmados (aparecem em combate)
    - Nicknames pending (detectados mas não confirmados)
    - Nicknames permanentes (jogador local)
    """

    def __init__(self):
        # Nicknames confirmados (actor_id → nome)
        self.nicknames: Dict[int, str] = {}

        # Nicknames pendentes (aguardando confirmação via combate)
        self.pending: Dict[int, str] = {}

        # Nicknames permanentes (não são resetados)
        self.permanent: Dict[int, str] = {}

        # Actor IDs que apareceram em combate
        self.combat_actors: Set[int] = set()

    def set_nickname(self, actor_id: int, name: str, permanent: bool = False):
        """
        Define nickname de um actor.

        Args:
            actor_id: ID do actor/entidade
            name: Nome (nickname)
            permanent: Se True, não será resetado
        """
        # Validar nome
        if not self._is_valid_nickname(name):
            logger.debug(f"Nickname inválido rejeitado: '{name}'")
            return

        # Sanitizar nome
        sanitized = self._sanitize_nickname(name)
        if not sanitized:
            return

        if permanent:
            self.permanent[actor_id] = sanitized
            self.nicknames[actor_id] = sanitized
            logger.info(
                f"Nickname permanente definido: {actor_id} → '{sanitized}'")
        else:
            self.nicknames[actor_id] = sanitized
            logger.debug(f"Nickname definido: {actor_id} → '{sanitized}'")

    def set_pending_nickname(self, actor_id: int, name: str):
        """
        Define nickname pendente (aguardando confirmação).

        Args:
            actor_id: ID do actor
            name: Nome detectado
        """
        if actor_id in self.nicknames:
            return  # Já tem nickname confirmado

        sanitized = self._sanitize_nickname(name)
        if sanitized:
            self.pending[actor_id] = sanitized
            logger.debug(f"Nickname pendente: {actor_id} → '{sanitized}'")

    def get_nickname(self, actor_id: int) -> Optional[str]:
        """
        Obtém nickname de um actor.

        Args:
            actor_id: ID do actor

        Returns:
            Nome ou None se não conhecido
        """
        # Prioridade: permanent > confirmed > pending
        if actor_id in self.permanent:
            return self.permanent[actor_id]
        if actor_id in self.nicknames:
            return self.nicknames[actor_id]
        if actor_id in self.pending:
            return self.pending[actor_id]
        return None

    def has_nickname(self, actor_id: int) -> bool:
        """
        Verifica se um actor tem nickname conhecido.

        Args:
            actor_id: ID do actor

        Returns:
            True se conhecido
        """
        return actor_id in self.nicknames or \
            actor_id in self.pending or \
            actor_id in self.permanent

    def confirm_combat_actor(self, actor_id: int):
        """
        Marca actor como presente em combate.

        Se tem nickname pendente, promove para confirmado.

        Args:
            actor_id: ID do actor
        """
        self.combat_actors.add(actor_id)

        # Promover pending para confirmed
        if actor_id in self.pending and actor_id not in self.nicknames:
            self.nicknames[actor_id] = self.pending[actor_id]
            logger.debug(
                f"Nickname confirmado via combate: {actor_id} → '{self.nicknames[actor_id]}'")

    def is_combat_actor(self, actor_id: int) -> bool:
        """
        Verifica se actor apareceu em combate.

        Args:
            actor_id: ID do actor

        Returns:
            True se apareceu em combate
        """
        return actor_id in self.combat_actors

    def reset_non_permanent(self):
        """
        Reseta todos os nicknames exceto permanentes.

        Útil ao resetar sessão de combate.
        """
        count_before = len(self.nicknames)

        # Limpar nicknames não-permanentes
        self.nicknames = {k: v for k,
                          v in self.nicknames.items() if k in self.permanent}

        # Restaurar permanentes
        self.nicknames.update(self.permanent)

        # Limpar pending e combat
        self.pending.clear()
        self.combat_actors.clear()

        count_after = len(self.nicknames)
        logger.info(
            f"Cache resetado: {count_before} → {count_after} nicknames (permanentes mantidos)")

    def get_all_nicknames(self) -> Dict[int, str]:
        """
        Retorna todos os nicknames conhecidos.

        Returns:
            Dicionário actor_id → nome
        """
        # Merge: confirmed + pending
        result = dict(self.nicknames)
        for actor_id, name in self.pending.items():
            if actor_id not in result:
                result[actor_id] = name
        return result

    def _is_valid_nickname(self, name: str) -> bool:
        """
        Valida se um nome é válido.

        Args:
            name: Nome a validar

        Returns:
            True se válido
        """
        if not name or len(name) < 2:
            return False

        if len(name) > 36:  # Max name length no AION 2
            return False

        # Rejeitar nomes com caracteres inválidos
        invalid_chars = ['\n', '\r', '\t', '\x00']
        if any(c in name for c in invalid_chars):
            return False

        return True

    def _sanitize_nickname(self, name: str) -> Optional[str]:
        """
        Sanitiza nickname removendo espaços e caracteres inválidos.

        Args:
            name: Nome bruto

        Returns:
            Nome sanitizado ou None se inválido
        """
        # Remover espaços nas pontas
        sanitized = name.strip()

        # Remover guild tags [TAG] se presente
        if sanitized.startswith('[') and ']' in sanitized:
            # Pular guild tag
            end_tag = sanitized.index(']')
            sanitized = sanitized[end_tag + 1:].strip()

        # Validar novamente
        if not self._is_valid_nickname(sanitized):
            return None

        return sanitized

    def __len__(self) -> int:
        """Retorna número total de nicknames conhecidos"""
        return len(self.get_all_nicknames())

    def __repr__(self) -> str:
        return f"NicknameCache(confirmed={len(self.nicknames)}, pending={len(self.pending)}, permanent={len(self.permanent)})"
